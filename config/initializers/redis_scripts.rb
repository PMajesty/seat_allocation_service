require "digest"

module RedisScripts
  ATOMIC_HOLD_BODY = <<~LUA
    local holds_z_key      = KEYS[1]
    local user_holds_z_key = KEYS[2]

    local showtime_id      = ARGV[1]
    local user_id          = ARGV[2]
    local ttl_seconds      = tonumber(ARGV[3])
    local max_per_user     = tonumber(ARGV[4])
    local is_trusted       = tonumber(ARGV[5])
    local untrusted_limit  = tonumber(ARGV[6])
    local allow_refresh    = tonumber(ARGV[7])

    local current_time     = tonumber(redis.call('TIME')[1])
    local expiry_timestamp = current_time + ttl_seconds
    local seat_key_prefix  = "seat_hold:" .. showtime_id .. ":"

    redis.call('ZREMRANGEBYSCORE', holds_z_key, '-inf', current_time)
    redis.call('ZREMRANGEBYSCORE', user_holds_z_key, '-inf', current_time)

    local active_holds_count = redis.call('ZCARD', holds_z_key)
    local user_holds_count   = redis.call('ZCARD', user_holds_z_key)

    local net_new_seats_needed = 0

    for i = 8, #ARGV do
      local seat_id = ARGV[i]
      local key = seat_key_prefix .. seat_id
      local current_holder = redis.call('GET', key)

      if current_holder ~= user_id then
        net_new_seats_needed = net_new_seats_needed + 1
      end
    end

    if (user_holds_count + net_new_seats_needed) > max_per_user then
      return { "error", "HOLD_LIMIT_EXCEEDED" }
    end

    if is_trusted == 0 and net_new_seats_needed > 0 then
      if (active_holds_count + net_new_seats_needed) > untrusted_limit then
        return { "error", "HOLD_CAP_REACHED_UNTRUSTED" }
      end
    end

    for i = 8, #ARGV do
      local seat_id = ARGV[i]
      local key = seat_key_prefix .. seat_id
      local current_holder = redis.call('GET', key)

      if current_holder and current_holder ~= user_id then
        return { "error", "SEAT_TAKEN", seat_id }
      end
    end

    local successfully_held_seats = {}

    for i = 8, #ARGV do
      local seat_id = ARGV[i]
      local key = seat_key_prefix .. seat_id
      local current_holder = redis.call('GET', key)

      local should_update = true

      if current_holder == user_id and allow_refresh == 0 then
        should_update = false
      end

      if should_update then
        redis.call('SET', key, user_id, 'EX', ttl_seconds)
        redis.call('ZADD', holds_z_key, expiry_timestamp, seat_id)
        redis.call('ZADD', user_holds_z_key, expiry_timestamp, seat_id)
      end

      table.insert(successfully_held_seats, seat_id)
    end

    return { "success", successfully_held_seats }
  LUA

  ATOMIC_RELEASE_BODY = <<~LUA
    local holds_z = KEYS[1]
    local user_holds_z = KEYS[2]
    local showtime_id = ARGV[1]
    local user_id = ARGV[2]
    local seat_key_prefix = "seat_hold:" .. showtime_id .. ":"

    for i = 3, #ARGV do
      local seat_id = ARGV[i]
      local key = seat_key_prefix .. seat_id
      local holder = redis.call('GET', key)

      if holder == user_id then
        redis.call('DEL', key)
        redis.call('ZREM', holds_z, seat_id)
        redis.call('ZREM', user_holds_z, seat_id)
      end
    end

    return { "success" }
  LUA

  ATOMIC_HOLD_SHA = Digest::SHA1.hexdigest(ATOMIC_HOLD_BODY)
  ATOMIC_RELEASE_SHA = Digest::SHA1.hexdigest(ATOMIC_RELEASE_BODY)
end
