module Api
  module V1
    class HoldsController < BaseController
      include ShowtimeBroadcaster

      def create
        service = HoldService.new(current_user, params[:id])
        result = service.hold!(params[:seat_ids] || [])

        if result[:success]
          broadcast_showtime_refresh(params[:id])
          render json: result, status: :ok
        else
          render json: result, status: :unprocessable_entity
        end
      end

      def destroy
        service = HoldService.new(current_user, params[:id])
        result = service.release!(params[:seat_ids] || [])

        broadcast_showtime_refresh(params[:id])
        render json: result, status: :ok
      end
    end
  end
end
