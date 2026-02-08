require "connection_pool"
require "redis"

redis_config = {
  url: ENV["REDIS_URL"],
  reconnect_attempts: 1
}

REDIS_POOL = ConnectionPool.new(size: ENV.fetch("RAILS_MAX_THREADS", 5).to_i, timeout: 5) do
  Redis.new(redis_config)
end
