module Api
  module V1
    class ShowtimesController < BaseController
      def seats
        seats = ShowtimeInventoryService.new(params[:id], current_user).call
        render json: seats
      end
    end
  end
end
