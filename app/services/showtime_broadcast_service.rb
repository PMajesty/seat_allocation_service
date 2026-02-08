class ShowtimeBroadcastService
  def self.call(showtime_id)
    new(showtime_id).call
  end

  def initialize(showtime_id)
    @showtime_id = showtime_id
  end

  def call
    REDIS_POOL.with do |conn|
      if conn.set("broadcast_lock:#{@showtime_id}", "1", px: 200, nx: true)
        conn.del("broadcast_pending:#{@showtime_id}")
        broadcast_now
        BroadcastCoalesceJob.set(wait: 0.5.seconds).perform_later(@showtime_id)
      else
        conn.set("broadcast_pending:#{@showtime_id}", "1")
      end
    end
  end

  private

  def broadcast_now
    ActionCable.server.broadcast("showtime_#{@showtime_id}", { event: "refresh" })
  end
end
