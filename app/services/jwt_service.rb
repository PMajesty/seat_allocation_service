class JwtService
  ALGORITHM = "HS256".freeze
  ISSUER = "showtime-api".freeze
  AUDIENCE = "showtime-app".freeze

  KEYS = {
    "kid_v1" => ENV["JWT_SECRET_KEY_V1"] || (Rails.env.development? || Rails.env.test? ? "stub_secret_v1" : nil),
    "kid_v2" => ENV["JWT_SECRET_KEY_V2"] || (Rails.env.development? || Rails.env.test? ? "stub_secret_v2" : nil)
  }.compact.freeze

  ACTIVE_KID = ENV.fetch("JWT_ACTIVE_KID", "kid_v2").freeze

  def self.encode(payload)
    payload = payload.dup
    payload[:exp] = 24.hours.from_now.to_i
    payload[:iat] ||= Time.current.to_i
    payload[:jti] ||= SecureRandom.uuid
    payload[:iss] = ISSUER
    payload[:aud] = AUDIENCE

    raise "Active key ID #{ACTIVE_KID} not found in KEYS" unless KEYS.key?(ACTIVE_KID)

    JWT.encode(payload, KEYS[ACTIVE_KID], ALGORITHM, { kid: ACTIVE_KID })
  end

  def self.decode(token)
    decoded = JWT.decode(
      token,
      nil,
      true,
      {
        algorithm: ALGORITHM,
        verify_iat: true,
        verify_expiration: true,
        verify_iss: true,
        iss: ISSUER,
        verify_aud: true,
        aud: AUDIENCE,
        verify_jti: true
      }
    ) do |header|
      KEYS[header["kid"]]
    end.first

    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError
    nil
  end
end
