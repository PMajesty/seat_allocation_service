class BroadcastCoalesceJob < ApplicationJob
  self.queue_adapter = :async unless Rails.env.test?
  queue_as :default

  include ShowtimeBroadcaster

  def perform(showtime_id)
    REDIS_POOL.with do |conn|
      if conn.get("broadcast_pending:#{showtime_id}")
        conn.del("broadcast_pending:#{showtime_id}")
        conn.set("broadcast_lock:#{showtime_id}", "1", px: 200)

        ActionCable.server.broadcast("showtime_#{showtime_id}", { event: "refresh" })
        BroadcastCoalesceJob.set(wait: 0.5.seconds).perform_later(showtime_id)
      end
    end
  end
end
