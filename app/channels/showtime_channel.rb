class ShowtimeChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "showtime_#{params[:showtime_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
