module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.headers["Authorization"]&.split&.last ||
              request.params[:token] ||
              cookies[:jwt]

      if token && (payload = JwtService.decode(token))
        if (user = User.find_by(id: payload["user_id"]))
          return user
        end
      end

      reject_unauthorized_connection
    end
  end
end
