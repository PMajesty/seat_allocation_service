module Api
  module V1
    class CheckoutsController < BaseController
      include ShowtimeBroadcaster

      def create
        seat_ids = params[:seat_ids] || []

        idempotency_key = request.headers["Idempotency-Key"] ||
                          params[:idempotency_key] ||
                          SecureRandom.uuid

        service = CheckoutService.new(current_user, params[:id])
        result = service.call(seat_ids, idempotency_key: idempotency_key)

        if result[:success]
          broadcast_showtime_refresh(params[:id])
          render json: result, status: :ok
        else
          render json: result, status: :unprocessable_entity
        end
      end
    end
  end
end
