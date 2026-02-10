module Api
  module V1
    class CheckoutsController < BaseController
      include ShowtimeBroadcaster

      def create
        seat_ids = params[:seat_ids] || []

        idempotency_key = request.headers["Idempotency-Key"] ||
                          params[:idempotency_key] ||
                          SecureRandom.uuid

        service = CheckoutStarter.new(current_user, params[:id])
        result = service.call(seat_ids, idempotency_key: idempotency_key)

        if result[:success]
          if result[:status] == :completed
            render json: { success: true, order_id: result[:order_id] }, status: :ok
          else
            render json: {
              success: true,
              status: "processing",
              message: "Payment is being processed.",
              payment_reference: result[:payment_reference]
            }, status: :accepted
          end
        else
          render json: result, status: :unprocessable_entity
        end
      end
    end
  end
end
