class PaymentSimulationJob < ApplicationJob
  queue_as :default

  def perform(payment_reference, user_id, showtime_id)
    sleep(rand(3.0..6.0))

    success = rand < 0.9
    gateway_response = {
      transaction_id: SecureRandom.uuid,
      timestamp: Time.current.iso8601,
      status: success ? "approved" : "declined",
      error_code: success ? nil : "card_declined"
    }

    user = User.find(user_id)
    service = CheckoutCallbackHandler.new(user, showtime_id)
    service.call(payment_reference, success, gateway_response)
  rescue => e
    Rails.logger.error("PaymentSimulationJob failed for ref #{payment_reference}: #{e.message}")
    handle_crash(user_id, showtime_id, payment_reference)
  end

  private

  def handle_crash(user_id, showtime_id, payment_reference)
    user = User.find_by(id: user_id)
    return unless user

    ActionCable.server.broadcast(
      "user_payment:#{user.id}",
      {
        status: "error",
        message: "An internal error occurred during payment processing.",
        code: "INTERNAL_ERROR",
        payment_reference: payment_reference
      }
    )
  end
end
