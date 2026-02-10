class SimulationJob < ApplicationJob
  queue_as :default
  include ShowtimeBroadcaster

  BATCH_SIZE = 100
  JOB_DURATION = 5.minutes

  BURST_INTERVAL = 1.second
  INVENTORY_REFRESH_INTERVAL = 5.seconds

  def perform
    current_mode = LoadSimulationService.current_mode
    return if current_mode == "off"

    all_scheduled_ids = Showtime.where(status: :scheduled).pluck(:id)
    if all_scheduled_ids.empty?
      sleep(5)
      return
    end

    seat_cache = build_seat_cache(all_scheduled_ids)
    users = create_user_batch(current_mode)
    my_holds = Hash.new { |h, k| h[k] = [] }

    end_time = Time.now + JOB_DURATION
    next_broadcast = Time.now + BURST_INTERVAL
    next_inventory_check = Time.now

    active_showtime_ids = []
    inventory_stats = {}

    begin
      while Time.now < end_time
        loop_start = Time.now
        current_mode = LoadSimulationService.current_mode
        break if current_mode == "off"

        if active_showtime_ids.empty? || Time.now >= next_inventory_check
          active_showtime_ids = filter_active_showtimes(all_scheduled_ids)

          unless active_showtime_ids.empty?
            refresh_inventory_stats(active_showtime_ids, inventory_stats)
            update_seat_cache(active_showtime_ids, seat_cache)
          end

          next_inventory_check = Time.now + INVENTORY_REFRESH_INTERVAL
        end

        if active_showtime_ids.empty?
          sleep(2)
          next
        end

        burst_size = calculate_burst_size(current_mode)

        if burst_size > 0
          users.sample(burst_size).each do |user|
            perform_user_action(current_mode, user, active_showtime_ids, seat_cache, my_holds, inventory_stats)
          end
        end

        if Time.now >= next_broadcast
          active_showtime_ids.each { |sid| broadcast_showtime_refresh(sid) }
          next_broadcast = Time.now + BURST_INTERVAL
        end

        elapsed = Time.now - loop_start
        sleep_time = [BURST_INTERVAL - elapsed, 0.1].max
        sleep(sleep_time)
      end
    ensure
      cleanup_users(users)
    end

    SimulationJob.perform_later if LoadSimulationService.current_mode != "off"
  end

  private

  def calculate_burst_size(mode)
    case mode
    when "bot" then 50
    when "high" then 15
    when "real" then 5
    else 0
    end
  end

  def perform_user_action(mode, user, showtime_ids, seat_cache, my_holds, stats)
    showtime_id = showtime_ids.sample
    return unless showtime_id

    if over_limit?(mode, stats[showtime_id])
      release_random_seat(user, showtime_id, my_holds)
      return
    end

    if mode == "bot"
      hold_random_seats(user, showtime_id, seat_cache, my_holds)
    else
      if rand < 0.7
        hold_random_seats(user, showtime_id, seat_cache, my_holds)
      else
        release_random_seat(user, showtime_id, my_holds)
      end
    end
  end

  def filter_active_showtimes(showtime_ids)
    return [] if showtime_ids.empty?

    counts = REDIS_POOL.with do |conn|
      conn.pipelined do |pipeline|
        showtime_ids.each { |id| pipeline.zcard("holds_z:#{id}") }
      end
    end

    showtime_ids.zip(counts).select { |_, count| count > 0 }.map(&:first)
  end

  def create_user_batch(mode)
    default_digest = "$2a$12$Gz.t.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y.y"
    now = Time.current
    trusted_time = 20.hours.ago

    user_attrs = BATCH_SIZE.times.map do
      is_trusted = mode != "bot" && rand < 0.5
      {
        email: "sim_#{SecureRandom.hex(6)}@simulation.local",
        password_digest: default_digest,
        role: :visitor,
        created_at: is_trusted ? trusted_time : now,
        updated_at: now
      }
    end

    result = User.insert_all(user_attrs, returning: %i[id email role])
    User.where(id: result.pluck("id")).to_a
  end

  def cleanup_users(users)
    return if users.empty?
    User.where(id: users.map(&:id)).delete_all
  end

  def build_seat_cache(showtime_ids)
    cache = {}
    cache
  end

  def update_seat_cache(showtime_ids, cache)
    showtime_ids.each do |sid|
      next if cache.key?(sid)

      response = ShowtimeInventoryService.new(sid).call
      inventory = JSON.parse(response[:public_grid_json], symbolize_names: true)
      cache[sid] = inventory.map { |s| s[:id] }
    end
  end

  def refresh_inventory_stats(showtime_ids, stats)
    showtime_ids.each do |sid|
      response = ShowtimeInventoryService.new(sid).call
      inventory = JSON.parse(response[:public_grid_json], symbolize_names: true)

      total = inventory.size
      sold = inventory.count { |s| s[:status] == "sold" }
      held = inventory.count { |s| s[:status] != "available" && s[:status] != "sold" }

      stats[sid] = { total: total, sold: sold, held: held, remaining: total - sold }
    end
  end

  def over_limit?(mode, stat)
    return false unless stat && ["real", "high", "bot"].include?(mode)

    limit_ratio = mode == "high" ? 0.8 : 0.5
    return false if stat[:remaining].zero?

    current_ratio = stat[:held].to_f / stat[:remaining]
    current_ratio > limit_ratio
  end

  def hold_random_seats(user, showtime_id, seat_cache, my_holds)
    count = mode_seat_count
    return unless seat_cache[showtime_id]

    potential_seats = seat_cache[showtime_id].sample(count)
    return if potential_seats.empty?

    begin
      HoldService.new(user, showtime_id).hold!(potential_seats)
      my_holds[user.id].concat(potential_seats)
    rescue StandardError
    end
  end

  def release_random_seat(user, showtime_id, my_holds)
    held_seats = my_holds[user.id]
    return if held_seats.empty?

    seats_to_release = held_seats.sample(rand(1..mode_seat_count))

    begin
      HoldService.new(user, showtime_id).release!(seats_to_release)
      my_holds[user.id] -= seats_to_release
    rescue StandardError
    end
  end

  def mode_seat_count
    rand(1..HoldService::MAX_PER_USER)
  end
end
