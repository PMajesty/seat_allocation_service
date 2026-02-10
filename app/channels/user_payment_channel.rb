class UserPaymentChannel < ActionCable::Channel::Base
  def subscribed
    reject unless current_user
    stream_from "user_payment:#{current_user.id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
