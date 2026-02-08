class SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      token = JwtService.encode(user_id: user.id, ver: user.token_version)
      cookies[:jwt] = {
        value: token,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: 24.hours.from_now
      }

      respond_to do |format|
        format.json { render json: { message: "Logged in successfully." }, status: :ok }
        format.html { redirect_to dashboard_path, notice: "Logged in successfully." }
      end
    else
      respond_to do |format|
        format.json { render json: { error: "Invalid email or password." }, status: :unauthorized }
        format.html do
          flash.now[:alert] = "Invalid email or password."
          render :new, status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    cookies.delete(:jwt)
    redirect_to root_path, notice: "Logged out."
  end
end
