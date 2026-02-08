class CleanupExpiredHoldsJob < ApplicationJob
  queue_as :default

  def perform(showtime_id = nil)
    if showtime_id
      clean_holds(showtime_id)
    else
      Showtime.where("starts_at > ?", Time.current).find_each do |showtime|
        clean_holds(showtime.id)
      end
    end
  end

  private

  def clean_holds(showtime_id)
    REDIS_POOL.with do |conn|
      holds_z_key = "holds_z:#{showtime_id}"

      conn.zremrangebyscore(holds_z_key, "-inf", Time.current.to_i)

      held_seat_ids = conn.zrange(holds_z_key, 0, -1)
      return if held_seat_ids.empty?

      existence_results = conn.pipelined do |pipeline|
        held_seat_ids.each do |seat_id|
          pipeline.exists("seat_hold:#{showtime_id}:#{seat_id}")
        end
      end

      orphaned_ids = []
      held_seat_ids.each_with_index do |seat_id, index|
        if existence_results[index] == 0
          orphaned_ids << seat_id
        end
      end

      if orphaned_ids.any?
        conn.zrem(holds_z_key, orphaned_ids)
        held_seat_ids -= orphaned_ids
      end

      return if held_seat_ids.empty?

      sold_seat_ids = ShowtimeSeat.where(
        showtime_id: showtime_id,
        seat_id: held_seat_ids,
        status: :sold
      ).pluck(:seat_id).map(&:to_s)

      if sold_seat_ids.any?
        conn.pipelined do |pipeline|
          pipeline.zrem(holds_z_key, sold_seat_ids)
          sold_seat_ids.each do |seat_id|
            pipeline.del("seat_hold:#{showtime_id}:#{seat_id}")
          end
        end
      end
    end
  end
end
