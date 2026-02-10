class CleanupSimulationWorker < ApplicationWorker
  from_queue "cleanup_simulation", env: nil

  include ShowtimeBroadcaster

  def perform
    Showtime.where(status: :scheduled).find_each do |showtime|
      holds_map = fetch_holds_from_redis(showtime.id)
      next if holds_map.empty?

      holder_ids = holds_map.values.uniq

      real_user_ids = User.where(id: holder_ids)
                          .where.not("email LIKE ?", "%@simulation.local")
                          .pluck(:id)

      seats_to_release = holds_map.select do |_, user_id|
        !real_user_ids.include?(user_id)
      end

      if seats_to_release.any?
        seats_to_release.group_by { |_, user_id| user_id }.each do |user_id, seat_pairs|
          seat_ids = seat_pairs.map(&:first)
          user = Struct.new(:id).new(user_id)
          HoldService.new(user, showtime.id).release!(seat_ids)
        end
        broadcast_showtime_refresh(showtime.id)
      end
    end

    User.where("email LIKE ?", "%@simulation.local").delete_all
  end

  private

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
