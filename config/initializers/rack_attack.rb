class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL"),
    namespace: "rack-attack"
  )

  safelist("allow-localhost") { |req| req.ip == "127.0.0.1" || req.ip == "::1" }

  throttle("signup_ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/signup" && req.post?
  end

  throttle("login_ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/login" && req.post?
  end

  throttle("login_email", limit: 10, period: 1.minute) do |req|
    if req.path == "/login" && req.post?
      email = req.params["email"].to_s.strip.downcase
      email.presence
    end
  end

  throttle("holds_ip", limit: 50, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/api/v1/showtimes/\d+/holds\z}) && req.post?
  end

  throttle("checkout_ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/api/v1/showtimes/\d+/checkout\z}) && req.post?
  end

  throttle("seats_polling_ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/api/v1/showtimes/\d+/seats\z}) && req.get?
  end

  throttle("search_ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/" && req.params["q"].present?
  end

  throttle("web_ip", limit: 60, period: 1.minute) do |req|
    unless req.path.start_with?("/api/", "/assets", "/rails/active_storage", "/up")
      req.ip
    end
  end
end
