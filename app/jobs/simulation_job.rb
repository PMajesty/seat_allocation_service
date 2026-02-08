class SimulationJob < ApplicationJob
  queue_as :default
  include ShowtimeBroadcaster

  BATCH_SIZE = 20

  def perform
    mode = LoadSimulationService.current_mode
    return if mode == "off"

    showtime_ids = Showtime.where(status: :scheduled).pluck(:id)
    return if showtime_ids.empty?

    users = create_user_batch(mode)

    end_time = Time.now + 30.seconds

    begin
      while Time.now < end_time
        mode = LoadSimulationService.current_mode
        break if mode == "off"

        simulate_activity(mode, users, showtime_ids)

        sleep_interval =
          case mode
          when "real" then rand(1.0..3.0)
          when "high" then rand(0.1..0.5)
          when "bot" then rand(0.2..0.5)
          else 1
          end
        sleep(sleep_interval)
      end
    ensure
      cleanup_users(users)
    end

    SimulationJob.perform_later if mode != "off"
  end

  private

  def create_user_batch(mode)
    users = []
    BATCH_SIZE.times do
      suffix = SecureRandom.hex(4)
      email = "sim_#{suffix}@simulation.local"

      user = User.create(email: email, password: "password", role: :visitor)

      is_trusted = mode != "bot" && rand < 0.5
      user.update_column(:created_at, 20.hours.ago) if is_trusted

      users << user
    end
    users
  end

  def cleanup_users(users)
    return unless users.present?
    User.where(id: users.map(&:id)).delete_all
  end

  def simulate_activity(mode, users, showtime_ids)
    user = users.sample
    return unless user

    showtime_id = showtime_ids.sample
    return unless showtime_id

    service_response = ShowtimeInventoryService.new(showtime_id).call
    inventory = JSON.parse(service_response[:public_grid_json], symbolize_names: true)

    enforce_load_limits(mode, showtime_id, inventory, users)
    return if over_limit?(mode, inventory)

    if mode == "bot"
      available_seats = inventory.select { |s| s[:status] == "available" }
                          .sample(HoldService::MAX_PER_USER)
                          .map { |s| s[:id] }

      if available_seats.any?
        HoldService.new(user, showtime_id).hold!(available_seats)
        broadcast_showtime_refresh(showtime_id)
      end
    else
      action = rand < 0.7 ? :hold : :release

      if action == :hold
        available_seats = inventory.select { |s| s[:status] == "available" }
                            .sample(rand(1..HoldService::MAX_PER_USER))
                            .map { |s| s[:id] }

        if available_seats.any?
          HoldService.new(user, showtime_id).hold!(available_seats)
          broadcast_showtime_refresh(showtime_id)
        end
      else
        holds_map = fetch_holds_from_redis(showtime_id)
        user_seat_ids = holds_map.select { |_, holder_id| holder_id == user.id }.keys

        if user_seat_ids.any?
          seats_to_release = user_seat_ids.sample(rand(1..HoldService::MAX_PER_USER))
          HoldService.new(user, showtime_id).release!(seats_to_release)
          broadcast_showtime_refresh(showtime_id)
        end
      end
    end
  end

  def over_limit?(mode, inventory)
    return false unless ["real", "high", "bot"].include?(mode)

    limit_ratio = mode == "high" ? 0.8 : 0.5

    total_seats = inventory.size
    sold_seats = inventory.count { |s| s[:status] == "sold" }
    remaining_seats = total_seats - sold_seats

    return false if remaining_seats.zero?

    held_seats_count = inventory.count { |s| s[:status] != "available" && s[:status] != "sold" }
    current_ratio = held_seats_count.to_f / remaining_seats

    current_ratio > limit_ratio
  end

  def enforce_load_limits(mode, showtime_id, inventory, users)
    return unless ["real", "high", "bot"].include?(mode)

    if over_limit?(mode, inventory)
      holds_map = fetch_holds_from_redis(showtime_id)
      sim_user_ids = users.map(&:id)

      sim_seat_ids = holds_map.select { |_, holder_id| sim_user_ids.include?(holder_id) }.keys

      sim_seat_ids.sample(2).each do |seat_id|
        holder_id = holds_map[seat_id]
        user = users.find { |u| u.id == holder_id }
        next unless user

        HoldService.new(user, showtime_id).release!([seat_id])
        broadcast_showtime_refresh(showtime_id)
      end
    end
  end

  def fetch_holds_from_redis(showtime_id)
    REDIS_POOL.with do |conn|
      seat_ids = conn.zrange("holds_z:#{showtime_id}", 0, -1)
      return {} if seat_ids.empty?

      keys = seat_ids.map { |sid| "seat_hold:#{showtime_id}:#{sid}" }
      values = conn.mget(keys)

      seat_ids.zip(values).each_with_object({}) do |(seat_id, holder_id), map|
        map[seat_id.to_i] = holder_id.to_i if holder_id
      end
    end
  end
end
