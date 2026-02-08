class Rack::Attack
  self.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])

  throttle("signup_ip", limit: 5, period: 1.minute) do |req|
    if req.path == "/signup" && req.post?
      req.ip
    end
  end

  throttle("login_ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/login" && req.post?
      req.ip
    end
  end

  throttle("holds_ip", limit: 100, period: 1.minute) do |req|
    if req.path.match?(%r{^/api/v1/showtimes/\d+/holds$}) && req.post?
      req.ip
    end
  end
end
