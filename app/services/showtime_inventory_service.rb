class ShowtimeInventoryService
  def initialize(showtime_id, current_user = nil)
    @showtime_id = showtime_id
    @current_user = current_user
  end

  def call
    public_grid_json = generate_public_grid
    user_context = fetch_user_context

    {
      public_grid_json: public_grid_json,
      user_context: user_context
    }
  end

  private

  attr_reader :showtime_id, :current_user

  def generate_public_grid
    seats = ShowtimeSeat.includes(:seat, :order)
                        .where(showtime_id: showtime_id)
                        .order("seats.grid_row ASC, seats.grid_col ASC")

    held_map = fetch_global_held_seats_map

    grid_data = seats.map do |ss|
      status = determine_public_status(ss, held_map[ss.seat.id])

      {
        id: ss.seat.id,
        row: ss.seat.grid_row,
        col: ss.seat.grid_col,
        status: status,
        price: ss.price_cents,
        type: "Standard",
        user_id: nil
      }
    end

    grid_data.to_json
  end

  def fetch_user_context
    return { held_ids: [], sold_ids: [] } unless current_user

    {
      held_ids: fetch_user_held_ids,
      sold_ids: fetch_user_sold_ids
    }
  end

  def fetch_user_sold_ids
    ShowtimeSeat.joins(:order)
                .where(showtime_id: showtime_id, orders: { user_id: current_user.id })
                .pluck(:seat_id)
  end

  def fetch_user_held_ids
    REDIS_POOL.with do |conn|
      now = Time.current.to_i
      held_seat_ids = conn.zrangebyscore("holds_z:#{showtime_id}", "(#{now}", "+inf")

      return [] if held_seat_ids.empty?

      keys = held_seat_ids.map { |sid| "seat_hold:#{showtime_id}:#{sid}" }
      holder_ids = conn.mget(keys)

      held_seat_ids.zip(holder_ids).select do |_, holder_id|
        holder_id.to_i == current_user.id
      end.map(&:first).map(&:to_i)
    end
  end

  def fetch_global_held_seats_map
    REDIS_POOL.with do |conn|
      now = Time.current.to_i
      held_seat_ids = conn.zrangebyscore("holds_z:#{showtime_id}", "(#{now}", "+inf")

      return {} if held_seat_ids.empty?

      held_seat_ids.each_with_object({}) { |id, map| map[id.to_i] = true }
    end
  end

  def determine_public_status(showtime_seat, is_held)
    if showtime_seat.available? && is_held
      "held"
    else
      showtime_seat.status
    end
  end
end
