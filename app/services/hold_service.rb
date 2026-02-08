class HoldService
  HOLD_TTL = 60
  MAX_PER_USER = 3
  MAX_PURCHASE_PER_ORDER = 6
  VIP_CUTOFF_RATIO = 0.20

  CAPACITY_CACHE_TTL = 24.hours
  SOLD_COUNT_CACHE_TTL = 15.seconds

  ERROR_MESSAGES = {
    "HOLD_LIMIT_EXCEEDED" => "You have reached the maximum number of holds allowed.",
    "HOLD_CAP_REACHED_UNTRUSTED" => "Due to high demand, seat availability is limited.",
    "SEAT_TAKEN" => "One or more selected seats are no longer available."
  }.freeze

  def initialize(user, showtime_id)
    @user = user
    @showtime_id = showtime_id
  end

  def hold!(seat_ids, bypass_limit: false, refresh: false)
    return { success: false, message: "No seats selected", code: "NO_SEATS_SELECTED" } if seat_ids.blank?

    normalized_seat_ids = seat_ids.map(&:to_i).uniq
    limit = bypass_limit ? MAX_PURCHASE_PER_ORDER : MAX_PER_USER

    if normalized_seat_ids.size > limit
      return { success: false, message: ERROR_MESSAGES["HOLD_LIMIT_EXCEEDED"], code: "HOLD_LIMIT_EXCEEDED" }
    end

    unless validate_seats_belong_to_showtime(normalized_seat_ids)
      return { success: false, message: "Invalid seat selection.", code: "INVALID_SEAT_SELECTION" }
    end

    if locked_out?
      return { success: false, message: "You are temporarily locked out due to payment failures.", code: "PAYMENT_LOCKOUT" }
    end

    sold_count = fetch_sold_count
    untrusted_limit = calculate_untrusted_limit(sold_count)
    is_trusted = trusted_user? ? 1 : 0
    allow_refresh = refresh ? 1 : 0

    keys = [holds_z_key, user_holds_z_key]
    argv = [
      @showtime_id,
      @user.id,
      HOLD_TTL,
      limit,
      is_trusted,
      untrusted_limit,
      allow_refresh,
      *normalized_seat_ids
    ]

    result = eval_lua(
      RedisScripts::ATOMIC_HOLD_SHA,
      RedisScripts::ATOMIC_HOLD_BODY,
      keys,
      argv
    )

    if result[0] == "success"
      if validate_seats_belong_to_showtime(normalized_seat_ids)
        { success: true, held_seat_ids: result[1] }
      else
        release!(normalized_seat_ids)
        { success: false, message: ERROR_MESSAGES["SEAT_TAKEN"], code: "SEAT_TAKEN" }
      end
    else
      code = result[1]
      message = ERROR_MESSAGES[code] || "An unexpected error occurred."
      { success: false, message: message, code: code, details: result[2] }
    end
  end

  def release!(seat_ids)
    return { success: false, message: "No seats selected", code: "NO_SEATS_SELECTED" } if seat_ids.empty?

    keys = [holds_z_key, user_holds_z_key]
    argv = [@showtime_id, @user.id, *seat_ids]

    eval_lua(
      RedisScripts::ATOMIC_RELEASE_SHA,
      RedisScripts::ATOMIC_RELEASE_BODY,
      keys,
      argv
    )
    { success: true }
  end

  private

  def holds_z_key
    "holds_z:#{@showtime_id}"
  end

  def user_holds_z_key
    "user_holds_z:#{@showtime_id}:#{@user.id}"
  end

  def trusted_user?
    @user.created_at < 10.hours.ago
  end

  def locked_out?
    REDIS_POOL.with do |conn|
      conn.get("checkout_lockout:#{@user.id}")
    end
  end

  def calculate_untrusted_limit(sold_count)
    total_capacity = fetch_total_capacity
    remaining_capacity = total_capacity - sold_count
    (remaining_capacity * (1 - VIP_CUTOFF_RATIO)).floor
  end

  def fetch_total_capacity
    Rails.cache.fetch("showtime_capacity:#{@showtime_id}", expires_in: CAPACITY_CACHE_TTL) do
      ShowtimeSeat.where(showtime_id: @showtime_id).count
    end
  end

  def fetch_sold_count
    Rails.cache.fetch("showtime_sold_count:#{@showtime_id}", expires_in: SOLD_COUNT_CACHE_TTL) do
      ShowtimeSeat.where(showtime_id: @showtime_id, status: :sold).count
    end
  end

  def validate_seats_belong_to_showtime(seat_ids)
    valid_ids = ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids, status: :available).pluck(:seat_id)
    valid_ids.size == seat_ids.size
  end

  def eval_lua(sha, body, keys, argv)
    REDIS_POOL.with do |conn|
      conn.evalsha(sha, keys: keys, argv: argv)
    rescue Redis::CommandError => e
      raise unless e.message.include?("NOSCRIPT")

      conn.script(:load, body)
      conn.evalsha(sha, keys: keys, argv: argv)
    end
  end
end
