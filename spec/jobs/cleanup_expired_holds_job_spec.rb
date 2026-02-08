require 'rails_helper'

RSpec.describe CleanupExpiredHoldsJob, type: :job, redis: true do
  include ActiveSupport::Testing::TimeHelpers

  let(:venue) { Venue.create!(name: "Test Venue", grid_rows: 5, grid_cols: 5) }
  let(:event) { Event.create!(title: "Test Event", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.hour.from_now) }
  let(:user) { User.create!(email: "holder@example.com", password: "12345678") }
  let(:showtime_id) { showtime.id }
  let(:now) { Time.current.to_i }

  def create_seat(row, col, status = :available)
    seat = Seat.create!(venue: venue, grid_row: row, grid_col: col)

    order = nil
    if status == :sold || status == 1
      order = Order.create!(user: user, showtime: showtime)
    end

    ShowtimeSeat.create!(showtime: showtime, seat: seat, status: status, order: order)
    seat
  end

  it "reconciles holds: removes expired, orphans, and sold seats" do
    expired_seat = create_seat(1, 1)
    orphaned_seat = create_seat(1, 2)
    sold_seat = create_seat(1, 3, :sold)
    valid_seat = create_seat(1, 4)

    REDIS_POOL.with do |conn|
      conn.zadd("holds_z:#{showtime_id}", now - 10, expired_seat.id)
      conn.set("seat_hold:#{showtime_id}:#{expired_seat.id}", "user_1")
      conn.zadd("holds_z:#{showtime_id}", now + 60, orphaned_seat.id)
      conn.zadd("holds_z:#{showtime_id}", now + 60, sold_seat.id)
      conn.set("seat_hold:#{showtime_id}:#{sold_seat.id}", "user_2")
      conn.zadd("holds_z:#{showtime_id}", now + 60, valid_seat.id)
      conn.set("seat_hold:#{showtime_id}:#{valid_seat.id}", "user_3")
    end

    travel_to Time.at(now) do
      described_class.perform_now(showtime_id)
    end

    REDIS_POOL.with do |conn|
      holds = conn.zrange("holds_z:#{showtime_id}", 0, -1)

      expect(holds).not_to include(expired_seat.id.to_s)
      expect(holds).not_to include(orphaned_seat.id.to_s)
      expect(holds).not_to include(sold_seat.id.to_s)
      expect(conn.exists("seat_hold:#{showtime_id}:#{sold_seat.id}")).to eq(0)
      expect(holds).to include(valid_seat.id.to_s)
      expect(conn.get("seat_hold:#{showtime_id}:#{valid_seat.id}")).to eq("user_3")
    end
  end
end
