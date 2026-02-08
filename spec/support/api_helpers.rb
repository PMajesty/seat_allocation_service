module ApiHelpers
  def jwt_headers(user)
    token = JwtService.encode(user_id: user.id, ver: user.token_version)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
