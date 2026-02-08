RSpec.configure do |config|
  config.before(:each, redis: true) do
    REDIS_POOL.with do |conn|
      conn.flushdb
      conn.script(:load, RedisScripts::ATOMIC_HOLD_BODY)
      conn.script(:load, RedisScripts::ATOMIC_RELEASE_BODY)
    end
  end

  config.after(:each, redis: true) do
    REDIS_POOL.with(&:flushdb)
  end
end
