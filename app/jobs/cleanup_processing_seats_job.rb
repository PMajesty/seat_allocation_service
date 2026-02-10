class CleanupProcessingSeatsJob < ApplicationJob
  queue_as :default
  include ShowtimeBroadcaster

  PROCESSING_TIMEOUT = 10.minutes

  def perform
    stuck_seats = ShowtimeSeat.where(status: :processing).where("updated_at < ?", PROCESSING_TIMEOUT.ago)
    return if stuck_seats.empty?

    stuck_seats.group_by(&:showtime_id).each do |showtime_id, seats|
      ShowtimeSeat.transaction do
        seat_ids = seats.map(&:id)
        locked_seats = ShowtimeSeat.where(id: seat_ids).lock("FOR UPDATE SKIP LOCKED").where(status: :processing)

        if locked_seats.any?
          locked_seats.update_all(status: :available, updated_at: Time.current)
          Rails.logger.info("Releasing stuck processing seats: #{locked_seats.map(&:id).join(', ')}")
        end
      end

      broadcast_showtime_refresh(showtime_id)
    end
  end
end
