module ShowtimeBroadcaster
  extend ActiveSupport::Concern

  included do
    def broadcast_showtime_refresh(showtime_id)
      ShowtimeBroadcastService.call(showtime_id)
    end
  end
end
