module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Helpers
      include ActionController::Cookies
      include ActionController::MimeResponds
      include ActionController::RequestForgeryProtection
      include Authenticatable

      protect_from_forgery with: :exception, if: -> { cookies[:jwt].present? }

      before_action :authenticate_user!
      rescue_from ActiveRecord::RecordNotFound, with: :not_found

      private

      def not_found
        render json: {
          success: false,
          code: "RESOURCE_NOT_FOUND",
          message: "The requested resource could not be found."
        }, status: :not_found
      end

      def authenticate_user!
        unless logged_in?
          render json: {
            success: false,
            code: "UNAUTHORIZED",
            message: "You must be logged in to perform this action."
          }, status: :unauthorized
        end
      end
    end
  end
end
