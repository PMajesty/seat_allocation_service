require 'rails_helper'

RSpec.describe "HoldService Redis Safety", type: :request, redis: true do
  let(:venue) { Venue.create!(name: "Venue", grid_rows: 5, grid_cols: 5) }
  let(:event) { Event.create!(title: "Event", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }

  let(:seats) do
    (1..5).flat_map do |row|
      (1..5).map { |col| Seat.create!(venue: venue, grid_row: row, grid_col: col) }
    end
  end

  before do
    seats.each do |seat|
      ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000, status: :available)
    end
  end

  describe "Atomic Holds & Concurrency" do
    it "prevents double booking when two users request the same seat simultaneously" do
      user1 = User.create!(email: "u1@test.com", password: "password123")
      user2 = User.create!(email: "u2@test.com", password: "password123")
      target_seat = seats.first

      t1 = Thread.new do
        Rails.application.executor.wrap do
          { user: user1, result: HoldService.new(user1, showtime.id).hold!([target_seat.id]) }
        end
      end

      t2 = Thread.new do
        Rails.application.executor.wrap do
          { user: user2, result: HoldService.new(user2, showtime.id).hold!([target_seat.id]) }
        end
      end

      results = [t1.value, t2.value]

      successes = results.select { |r| r[:result][:success] }
      failures = results.select { |r| !r[:result][:success] }

      expect(successes.count).to eq(1)
      expect(failures.count).to eq(1)
      expect(failures.first[:result][:code]).to eq("SEAT_TAKEN")

      successful_user = successes.first[:user]

      REDIS_POOL.with do |conn|
        holder_id = conn.get("seat_hold:#{showtime.id}:#{target_seat.id}")
        expect(holder_id).to eq(successful_user.id.to_s)
      end
    end
  end

  describe "Per-User Limits (Lua Enforcement)" do
    let(:user) { User.create!(email: "limit@test.com", password: "password123") }

    it "enforces the MAX_PER_USER limit strictly in Redis" do
      target_seats = seats[0..3]

      service = HoldService.new(user, showtime.id)

      result1 = service.hold!(target_seats[0..2].map(&:id))
      expect(result1[:success]).to be true
      expect(result1[:held_seat_ids].count).to eq(3)

      result2 = service.hold!([target_seats[3].id])
      expect(result2[:success]).to be false
      expect(result2[:code]).to eq("HOLD_LIMIT_EXCEEDED")

      REDIS_POOL.with do |conn|
        count = conn.zcard("user_holds_z:#{showtime.id}:#{user.id}")
        expect(count).to eq(3)
      end
    end
  end

  describe "Refresh Logic (allow_refresh)" do
    let(:user) { User.create!(email: "refresh@test.com", password: "password123") }
    let(:seat) { seats.first }
    let(:service) { HoldService.new(user, showtime.id) }
    let(:seat_key) { "seat_hold:#{showtime.id}:#{seat.id}" }

    it "extends TTL only when refresh is true" do
      service.hold!([seat.id])

      initial_ttl = REDIS_POOL.with { |c| c.ttl(seat_key) }
      expect(initial_ttl).to be_within(2).of(60)

      REDIS_POOL.with { |c| c.expire(seat_key, 30) }
      expect(REDIS_POOL.with { |c| c.ttl(seat_key) }).to be_within(2).of(30)

      service.hold!([seat.id], refresh: false)
      current_ttl = REDIS_POOL.with { |c| c.ttl(seat_key) }
      expect(current_ttl).to be_within(2).of(30)

      service.hold!([seat.id], refresh: true)
      refreshed_ttl = REDIS_POOL.with { |c| c.ttl(seat_key) }
      expect(refreshed_ttl).to be_within(2).of(60)
    end
  end

  describe "VIP Rope / Untrusted User Limits" do
    let(:trusted_user) { User.create!(email: "vip@test.com", password: "password123", created_at: 1.year.ago) }
    let(:untrusted_user) { User.create!(email: "newbie@test.com", password: "password123", created_at: 1.minute.ago) }

    before do
      sold_seats = seats[0..14]
      dummy_order = Order.create!(user: trusted_user, showtime: showtime, total_amount_cents: 0, status: :paid)
      ShowtimeSeat.where(seat: sold_seats).update_all(status: 1, order_id: dummy_order.id)
    end

    it "blocks untrusted users when the dynamic limit is reached" do
      HoldService.new(untrusted_user, showtime.id).hold!(seats[15..17].map(&:id))

      u2 = User.create!(email: "u2@test.com", password: "password123", created_at: 1.minute.ago)
      HoldService.new(u2, showtime.id).hold!(seats[18..20].map(&:id))

      u3 = User.create!(email: "u3@test.com", password: "password123", created_at: 1.minute.ago)
      HoldService.new(u3, showtime.id).hold!(seats[21..22].map(&:id))

      u4 = User.create!(email: "u4@test.com", password: "password123", created_at: 1.minute.ago)
      result = HoldService.new(u4, showtime.id).hold!([seats[23].id])

      expect(result[:success]).to be false
      expect(result[:code]).to eq("HOLD_CAP_REACHED_UNTRUSTED")
    end

    it "allows trusted users to bypass the untrusted limit" do
      REDIS_POOL.with do |conn|
        8.times { |i| conn.zadd("holds_z:#{showtime.id}", Time.now.to_i + 60, "mock_#{i}") }
      end

      result_untrusted = HoldService.new(untrusted_user, showtime.id).hold!([seats[23].id])
      expect(result_untrusted[:success]).to be false
      expect(result_untrusted[:code]).to eq("HOLD_CAP_REACHED_UNTRUSTED")

      result_trusted = HoldService.new(trusted_user, showtime.id).hold!([seats[23].id])
      expect(result_trusted[:success]).to be true
    end
  end
end
