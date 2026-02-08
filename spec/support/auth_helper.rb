module AuthHelper
  def login_as(user)
    post login_path, params: { email: user.email, password: user.password }
  end

  def api_login_as(user)
    token = JwtService.encode(user_id: user.id, ver: user.token_version)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelper, type: :request
end
