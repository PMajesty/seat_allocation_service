require 'rails_helper'

RSpec.describe CheckoutService, redis: true do
  let(:user) { User.create!(email: "lockout@example.com", password: "password", created_at: 1.day.ago) }

  let(:venue) { Venue.create!(name: "Test Venue", grid_rows: 5, grid_cols: 5) }
  let(:event) { Event.create!(title: "Test Event", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let!(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, status: :available, price_cents: 1000) }

  let(:service) { described_class.new(user, showtime.id) }
  let(:seat_ids) { [seat.id.to_s] }

  before do
    REDIS_POOL.with do |conn|
      conn.set("seat_hold:#{showtime.id}:#{seat.id}", user.id.to_s)
      conn.zadd("holds_z:#{showtime.id}", Time.now.to_i + 60, seat.id.to_s)
    end

    allow(service).to receive(:simulate_payment_latency)
  end

  describe "Payment Failure Lockout" do
    context "when payment fails once" do
      before do
        allow(service).to receive(:payment_failure?).and_return(true)
      end

      it "increments failure counter but does not lock out" do
        result = service.call(seat_ids)

        expect(result[:success]).to be false
        expect(result[:message]).to include('Payment failed (Simulated). Please try again.')

        count = REDIS_POOL.with { |c| c.get("payment_failures:#{user.id}") }
        expect(count).to eq("1")

        lockout = REDIS_POOL.with { |c| c.get("checkout_lockout:#{user.id}") }
        expect(lockout).to be_nil
      end
    end

    context "when payment fails twice" do
      before do
        allow(service).to receive(:payment_failure?).and_return(true)
        REDIS_POOL.with { |c| c.set("payment_failures:#{user.id}", "1") }
      end

      it "locks the user out and releases seats" do
        result = service.call(seat_ids)

        expect(result[:success]).to be false
        expect(result[:message]).to include("locked out")

        lockout = REDIS_POOL.with { |c| c.get("checkout_lockout:#{user.id}") }
        expect(lockout).to eq("1")

        hold_exists = REDIS_POOL.with { |c| c.exists?("seat_hold:#{showtime.id}:#{seat.id}") }
        expect(hold_exists).to be false
      end
    end

    context "when user is locked out" do
      before do
        REDIS_POOL.with { |c| c.set("checkout_lockout:#{user.id}", "1") }
      end

      it "prevents new holds via HoldService" do
        hold_service = HoldService.new(user, showtime.id)
        result = hold_service.hold!([seat.id])

        expect(result[:success]).to be false
        expect(result[:message]).to include("locked out")
      end
    end

    context "when payment succeeds" do
      before do
        allow(service).to receive(:payment_failure?).and_return(false)
        REDIS_POOL.with { |c| c.set("payment_failures:#{user.id}", "1") }
      end

      it "clears the failure counter" do
        result = service.call(seat_ids)

        expect(result[:success]).to be true

        count = REDIS_POOL.with { |c| c.get("payment_failures:#{user.id}") }
        expect(count).to be_nil
      end
    end
  end
end
