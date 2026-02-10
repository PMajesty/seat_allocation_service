class UserPaymentChannel < ActionCable::Channel::Base
  def subscribed
    if current_user
      stream_from "user_payment:#{current_user.id}"
      Rails.logger.info "[UserPaymentChannel] Subscribed to user_payment:#{current_user.id}"
    else
      Rails.logger.error "[UserPaymentChannel] Rejected subscription: No current_user"
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end
end
