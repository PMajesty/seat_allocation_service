require 'rails_helper'

RSpec.describe HoldService, redis: true do
  let(:user) { User.create!(email: "service@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "ServiceVenue", grid_rows: 2, grid_cols: 2) }
  let(:event) { Event.create!(title: "ServiceEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat1) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let(:seat2) { Seat.create!(venue: venue, grid_row: 1, grid_col: 2) }
  let(:seat3) { Seat.create!(venue: venue, grid_row: 2, grid_col: 1) }
  let(:seat4) { Seat.create!(venue: venue, grid_row: 2, grid_col: 2) }

  let!(:ss1) { ShowtimeSeat.create!(showtime: showtime, seat: seat1, price_cents: 1000, status: :available) }
  let!(:ss2) { ShowtimeSeat.create!(showtime: showtime, seat: seat2, price_cents: 1000, status: :available) }
  let!(:ss3) { ShowtimeSeat.create!(showtime: showtime, seat: seat3, price_cents: 1000, status: :available) }
  let!(:ss4) { ShowtimeSeat.create!(showtime: showtime, seat: seat4, price_cents: 1000, status: :available) }

  subject { described_class.new(user, showtime.id) }

  describe "#hold!" do
    it "returns success when seat is available" do
      result = subject.hold!([seat1.id])
      expect(result[:success]).to be true
      expect(result[:held_seat_ids]).to include(seat1.id.to_s)

      REDIS_POOL.with do |conn|
        expect(conn.get("seat_hold:#{showtime.id}:#{seat1.id}")).to eq(user.id.to_s)
      end
    end

    it "returns error when seat is taken by another user" do
      other_user = User.create!(email: "other@test.com", password: "password")
      HoldService.new(other_user, showtime.id).hold!([seat1.id])

      result = subject.hold!([seat1.id])
      expect(result[:success]).to be false
      expect(result[:message]).to eq("One or more selected seats are no longer available.")
      expect(result[:code]).to eq("SEAT_TAKEN")
      expect(result[:details]).to include(seat1.id.to_s)
    end

    it "returns error if seat_ids is empty" do
      result = subject.hold!([])
      expect(result[:success]).to be false
      expect(result[:message]).to eq("No seats selected")
      expect(result[:code]).to eq("NO_SEATS_SELECTED")
    end

    it "returns error if seat is already sold" do
      other_order = Order.create!(user: user, showtime: showtime, total_amount_cents: 1000, status: :paid)
      ss1.update!(status: :sold, order: other_order)

      result = subject.hold!([seat1.id])

      expect(result[:success]).to be false
      expect(result[:message]).to eq("Invalid seat selection.")
      expect(result[:code]).to eq("INVALID_SEAT_SELECTION")
    end

    context "input validation and normalization" do
      it "returns error immediately if seat_ids count exceeds MAX_PER_USER" do
        excessive_ids = (1..4).to_a
        expect(ShowtimeSeat).not_to receive(:where)

        result = subject.hold!(excessive_ids)

        expect(result[:success]).to be false
        expect(result[:message]).to eq("You have reached the maximum number of holds allowed.")
        expect(result[:code]).to eq("HOLD_LIMIT_EXCEEDED")
      end

      it "returns error immediately if seat_ids count exceeds MAX_PURCHASE_PER_ORDER when bypassing limit" do
        excessive_ids = (1..7).to_a
        expect(ShowtimeSeat).not_to receive(:where)

        result = subject.hold!(excessive_ids, bypass_limit: true)

        expect(result[:success]).to be false
        expect(result[:message]).to eq("You have reached the maximum number of holds allowed.")
        expect(result[:code]).to eq("HOLD_LIMIT_EXCEEDED")
      end

      it "normalizes duplicates before checking limit" do
        duplicate_ids = [seat1.id, seat1.id, seat2.id, seat2.id, seat1.id, seat2.id]

        result = subject.hold!(duplicate_ids)

        expect(result[:success]).to be true
        expect(result[:held_seat_ids].count).to eq(2)
      end

      it "normalizes string inputs to integers" do
        string_ids = [seat1.id.to_s, seat2.id.to_s]
        result = subject.hold!(string_ids)
        expect(result[:success]).to be true
      end
    end

    context "trusted user logic" do
      it "considers user trusted if created more than 10 hours ago" do
        user.update!(created_at: 11.hours.ago)
        result = subject.hold!([seat1.id])
        expect(result[:success]).to be true
      end

      it "considers user untrusted if created less than 10 hours ago" do
        user.update!(created_at: 9.hours.ago)
        result = subject.hold!([seat1.id])
        expect(result[:success]).to be true
      end
    end

    context "lockout check" do
      it "returns error if user is locked out" do
        REDIS_POOL.with { |conn| conn.set("checkout_lockout:#{user.id}", "1") }

        result = subject.hold!([seat1.id])

        expect(result[:success]).to be false
        expect(result[:code]).to eq("PAYMENT_LOCKOUT")
      end
    end

    context "bypass_limit option" do
      before { user.update!(created_at: 1.year.ago) }

      it "allows holding more than MAX_PER_USER when true" do
        subject.hold!([seat1.id, seat2.id, seat3.id])

        result = subject.hold!([seat4.id], bypass_limit: true)

        expect(result[:success]).to be true
        expect(result[:held_seat_ids]).to include(seat4.id.to_s)
      end

      it "fails holding more than MAX_PER_USER when false" do
        subject.hold!([seat1.id, seat2.id, seat3.id])

        result = subject.hold!([seat4.id], bypass_limit: false)

        expect(result[:success]).to be false
        expect(result[:code]).to eq("HOLD_LIMIT_EXCEEDED")
      end
    end

    context "refresh option" do
      it "extends TTL when refresh is true" do
        subject.hold!([seat1.id])
        sleep 1
        decayed_ttl = REDIS_POOL.with { |conn| conn.ttl("seat_hold:#{showtime.id}:#{seat1.id}") }

        subject.hold!([seat1.id], refresh: true)
        new_ttl = REDIS_POOL.with { |conn| conn.ttl("seat_hold:#{showtime.id}:#{seat1.id}") }

        expect(new_ttl).to be > decayed_ttl
      end

      it "does not extend TTL when refresh is false" do
        subject.hold!([seat1.id])
        sleep 1
        decayed_ttl = REDIS_POOL.with { |conn| conn.ttl("seat_hold:#{showtime.id}:#{seat1.id}") }

        subject.hold!([seat1.id], refresh: false)
        new_ttl = REDIS_POOL.with { |conn| conn.ttl("seat_hold:#{showtime.id}:#{seat1.id}") }

        expect(new_ttl).to be <= decayed_ttl
      end
    end

    context "when VIP cap is reached via sold seats" do
      let(:vip_venue) { Venue.create!(name: "VIPVenue", grid_rows: 2, grid_cols: 5) }
      let(:vip_showtime) { Showtime.create!(event: event, venue: vip_venue, starts_at: 1.day.from_now) }
      let(:vip_seats) do
        (1..10).map { |i| Seat.create!(venue: vip_venue, grid_row: 1, grid_col: i) }
      end

      before do
        dummy_order = Order.create!(user: user, showtime: vip_showtime, total_amount_cents: 1000, status: :paid)

        vip_seats.each_with_index do |seat, index|
          status = index < 9 ? :sold : :available
          if status == :sold
            ShowtimeSeat.create!(showtime: vip_showtime, seat: seat, price_cents: 1000, status: status, order: dummy_order)
          else
            ShowtimeSeat.create!(showtime: vip_showtime, seat: seat, price_cents: 1000, status: status)
          end
        end
      end

      let(:vip_service) { described_class.new(user, vip_showtime.id) }
      let(:available_seat) { vip_seats.last }

      it "blocks untrusted users when dynamic limit is reached" do
        user.update!(created_at: 1.minute.ago)

        result = vip_service.hold!([available_seat.id])

        expect(result[:success]).to be false
        expect(result[:code]).to eq("HOLD_CAP_REACHED_UNTRUSTED")
      end

      it "allows trusted users when dynamic limit is reached" do
        user.update!(created_at: 1.year.ago)

        result = vip_service.hold!([available_seat.id])

        expect(result[:success]).to be true
      end
    end
  end

  describe "#release!" do
    it "executes release script successfully" do
      subject.hold!([seat1.id])

      result = subject.release!([seat1.id])
      expect(result[:success]).to be true

      REDIS_POOL.with do |conn|
        expect(conn.exists?("seat_hold:#{showtime.id}:#{seat1.id}")).to be false
      end
    end

    it "returns failure if seat_ids is empty" do
      result = subject.release!([])
      expect(result[:success]).to be false
      expect(result[:code]).to eq("NO_SEATS_SELECTED")
    end
  end
end
