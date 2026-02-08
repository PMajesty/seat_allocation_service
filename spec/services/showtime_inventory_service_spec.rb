require 'rails_helper'

RSpec.describe ShowtimeInventoryService, redis: true do
  let(:user) { User.create!(email: "inv@example.com", password: "password") }
  let(:other_user) { User.create!(email: "other@example.com", password: "password") }

  let(:venue) { Venue.create!(name: "InvVenue", grid_rows: 1, grid_cols: 3) }
  let(:event) { Event.create!(title: "InvEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }

  let(:seat1) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let(:seat2) { Seat.create!(venue: venue, grid_row: 1, grid_col: 2) }
  let(:seat3) { Seat.create!(venue: venue, grid_row: 1, grid_col: 3) }

  let!(:order_me) { Order.create!(user: user, showtime: showtime, total_amount_cents: 1000, status: :paid) }
  let!(:order_other) { Order.create!(user: other_user, showtime: showtime, total_amount_cents: 1000, status: :paid) }

  let!(:ss1) { ShowtimeSeat.create!(showtime: showtime, seat: seat1, price_cents: 1000, status: :available) }
  let!(:ss2) { ShowtimeSeat.create!(showtime: showtime, seat: seat2, price_cents: 1000, status: :sold, order: order_me) }
  let!(:ss3) { ShowtimeSeat.create!(showtime: showtime, seat: seat3, price_cents: 1000, status: :sold, order: order_other) }

  subject { described_class.new(showtime.id, user) }

  def parse_result(result)
    grid = JSON.parse(result[:public_grid_json], symbolize_names: true)
    context = result[:user_context]
    [grid, context]
  end

  describe "#call" do
    it "returns seat data with correct statuses using real Redis data" do
      REDIS_POOL.with do |conn|
        conn.set("seat_hold:#{showtime.id}:#{seat1.id}", "123")
        conn.zadd("holds_z:#{showtime.id}", Time.now.to_i + 60, seat1.id.to_s)
      end

      result = subject.call
      grid, _ = parse_result(result)

      s1_result = grid.find { |r| r[:id] == seat1.id }
      expect(s1_result[:status]).to eq("held")
      expect(s1_result[:price]).to eq(1000)

      s2_result = grid.find { |r| r[:id] == seat2.id }
      expect(s2_result[:status]).to eq("sold")
    end

    it "handles empty redis holds" do
      result = subject.call
      grid, _ = parse_result(result)

      s1_result = grid.find { |r| r[:id] == seat1.id }
      expect(s1_result[:status]).to eq("available")
    end

    it "identifies ownership of sold seats via user_context" do
      result = subject.call
      grid, context = parse_result(result)

      s2_result = grid.find { |r| r[:id] == seat2.id }
      expect(s2_result[:status]).to eq("sold")
      expect(s2_result[:user_id]).to be_nil
      expect(context[:sold_ids]).to include(seat2.id)

      s3_result = grid.find { |r| r[:id] == seat3.id }
      expect(s3_result[:status]).to eq("sold")
      expect(context[:sold_ids]).not_to include(seat3.id)
    end

    it "identifies ownership of held seats via user_context" do
      REDIS_POOL.with do |conn|
        conn.set("seat_hold:#{showtime.id}:#{seat1.id}", user.id.to_s)
        conn.zadd("holds_z:#{showtime.id}", Time.now.to_i + 60, seat1.id.to_s)
      end

      result = subject.call
      grid, context = parse_result(result)

      s1_result = grid.find { |r| r[:id] == seat1.id }
      expect(s1_result[:status]).to eq("held")
      expect(s1_result[:user_id]).to be_nil
      expect(context[:held_ids]).to include(seat1.id)
    end
  end
end
