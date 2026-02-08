class CheckoutService
  include ShowtimeBroadcaster

  class CheckoutError < StandardError; end

  MAX_PURCHASE_PER_ORDER = 6

  def initialize(user, showtime_id)
    @user = user
    @showtime_id = showtime_id
  end

  def call(seat_ids, idempotency_key: nil)
    seat_ids = Array(seat_ids).map(&:to_i).uniq
    return { success: false, message: "No seats selected", code: "NO_SEATS_SELECTED" } if seat_ids.empty?

    if seat_ids.size > MAX_PURCHASE_PER_ORDER
      return { success: false, message: "Cannot purchase more than #{MAX_PURCHASE_PER_ORDER} seats per order.", code: "MAX_PURCHASE_EXCEEDED" }
    end

    unless validate_seats_belong_to_showtime(seat_ids)
      return { success: false, message: "Invalid seat selection.", code: "INVALID_SEAT_SELECTION" }
    end

    if idempotency_key.present?
      existing_payment = Payment.includes(:order).find_by(idempotency_key: idempotency_key, status: :successful)
      if existing_payment
        if existing_payment.order.user_id == @user.id
          return { success: true, order_id: existing_payment.order_id }
        else
          return { success: false, message: "This seat has already been paid for.", code: "SEAT_ALREADY_PAID" }
        end
      end
    end

    hold_result = ensure_all_seats_held(seat_ids)
    unless hold_result[:success]
      return {
        success: false,
        message: hold_result[:message] || "Could not secure all selected seats. Some may be taken.",
        code: hold_result[:code] || "SEAT_HOLD_FAILED"
      }
    end

    # The payments are synchronous and mocked. In a real production environment they would be async with a job, utilizing a new status
    simulate_payment_latency

    if payment_failure?
      handle_payment_failure(seat_ids)
    else
      clear_failure_counter
      process_successful_order(seat_ids, idempotency_key)
    end
  end

  private

  def validate_seats_belong_to_showtime(seat_ids)
    valid_ids = ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids).pluck(:seat_id)
    valid_ids.size == seat_ids.uniq.size
  end

  def ensure_all_seats_held(seat_ids)
    result = HoldService.new(@user, @showtime_id).hold!(seat_ids, bypass_limit: true, refresh: true)
    broadcast_showtime_refresh(@showtime_id) if result[:success]
    result
  end

  def simulate_payment_latency
    sleep(5.0)
  end

  # Simulated failures for testing purposes
  def payment_failure?
    rand < 0.1
  end

  def handle_payment_failure(seat_ids)
    failures = increment_failure_counter

    HoldService.new(@user, @showtime_id).release!(seat_ids)
    broadcast_showtime_refresh(@showtime_id)

    if failures >= 2
      lock_user_out
      clear_failure_counter
      { success: false, message: "Payment failed too many times. You are locked out for 1 minute.", code: "PAYMENT_LOCKOUT" }
    else
      { success: false, message: "Payment failed (Simulated). Please try again.", code: "PAYMENT_FAILED" }
    end
  end

  def increment_failure_counter
    key = "payment_failures:#{@user.id}"
    REDIS_POOL.with do |conn|
      count = conn.incr(key)
      conn.expire(key, 300)
      count
    end
  end

  def clear_failure_counter
    REDIS_POOL.with { |conn| conn.del("payment_failures:#{@user.id}") }
  end

  def lock_user_out
    REDIS_POOL.with { |conn| conn.set("checkout_lockout:#{@user.id}", "1", ex: 60) }
  end

  def process_successful_order(seat_ids, idempotency_key)
    order = nil

    begin
      ActiveRecord::Base.transaction do
        db_seats = ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids)
                               .lock("FOR UPDATE NOWAIT")
                               .index_by(&:seat_id)

        seat_ids.each do |id|
          seat = db_seats[id.to_i]
          if seat.nil? || !seat.available?
            raise CheckoutError, "One or more seats are no longer available."
          end
        end

        total_cents = db_seats.values.sum(&:price_cents)

        order = Order.create!(
          user: @user,
          showtime_id: @showtime_id,
          status: :paid,
          total_amount_cents: total_cents,
          currency: "USD"
        )

        Payment.create!(
          order: order,
          amount_cents: total_cents,
          currency: "USD",
          status: :successful,
          idempotency_key: idempotency_key
        )

        db_seats.values.each do |seat|
          seat.update!(status: :sold, order: order)
          Ticket.create!(order: order, showtime_seat: seat)
        end
      end
    rescue ActiveRecord::LockWaitTimeout
      HoldService.new(@user, @showtime_id).release!(seat_ids)
      broadcast_showtime_refresh(@showtime_id)
      return { success: false, message: "Seats are currently being processed by another user.", code: "SEAT_LOCKED" }
    rescue ActiveRecord::RecordNotUnique
      if idempotency_key.present?
        existing_payment = Payment.find_by(idempotency_key: idempotency_key, status: :successful)
        if existing_payment && existing_payment.order.user_id == @user.id
          HoldService.new(@user, @showtime_id).release!(seat_ids)
          broadcast_showtime_refresh(@showtime_id)
          return { success: true, order_id: existing_payment.order_id }
        end
      end

      HoldService.new(@user, @showtime_id).release!(seat_ids)
      broadcast_showtime_refresh(@showtime_id)
      return { success: false, message: "This seat has already been paid for.", code: "SEAT_ALREADY_PAID" }
    rescue CheckoutError => e
      HoldService.new(@user, @showtime_id).release!(seat_ids)
      broadcast_showtime_refresh(@showtime_id)
      return { success: false, message: e.message, code: "SEAT_NO_LONGER_AVAILABLE" }
    rescue => e
      HoldService.new(@user, @showtime_id).release!(seat_ids)
      broadcast_showtime_refresh(@showtime_id)
      return { success: false, message: "An unexpected error occurred during processing.", code: "INTERNAL_ERROR" }
    end

    begin
      HoldService.new(@user, @showtime_id).release!(seat_ids)
    rescue => e
      Rails.logger.error("Redis cleanup failed for Order #{order.id}: #{e.message}. Reconciliation: Keys will expire via TTL.")
    end

    { success: true, order_id: order.id }
  end
end
