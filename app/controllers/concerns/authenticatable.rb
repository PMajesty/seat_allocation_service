module Authenticatable
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :logged_in?
  end

  def current_user
    @current_user ||= find_user_by_token
  end

  def logged_in?
    current_user.present?
  end

  def authenticate_user!
    unless logged_in?
      respond_to do |format|
        format.html { redirect_to login_path, alert: "Please log in to continue." }
        format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
      end
    end
  end

  private

  def find_user_by_token
    token = request.headers["Authorization"]&.split(" ")&.last
    token ||= cookies[:jwt] if respond_to?(:cookies, true)
    return unless token

    payload = JwtService.decode(token)
    return unless payload

    user = Rails.cache.fetch("users/#{payload[:user_id]}", expires_in: 24.hours) do
      User.find_by(id: payload[:user_id])
    end

    return unless user && payload[:ver] == user.token_version

    user
  end
end
