require 'rails_helper'

RSpec.describe CheckoutStarter, redis: true do
  let(:user) { User.create!(email: "starter@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "StarterVenue", grid_rows: 2, grid_cols: 2) }
  let(:event) { Event.create!(title: "StarterEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat1) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let(:seat2) { Seat.create!(venue: venue, grid_row: 1, grid_col: 2) }

  let!(:ss1) { ShowtimeSeat.create!(showtime: showtime, seat: seat1, price_cents: 1000, status: :available) }
  let!(:ss2) { ShowtimeSeat.create!(showtime: showtime, seat: seat2, price_cents: 1000, status: :available) }

  let(:hold_service) { instance_double(HoldService) }

  subject { described_class.new(user, showtime.id) }

  before do
    allow(HoldService).to receive(:new).with(user, showtime.id).and_return(hold_service)
    allow(hold_service).to receive(:release!)
    allow(hold_service).to receive(:hold!).and_return({ success: true })

    allow(PaymentSimulationJob).to receive(:perform_later)
  end

  describe "#call" do
    context "validations" do
      it "returns error if seat_ids is empty" do
        result = subject.call([])
        expect(result[:success]).to be false
        expect(result[:code]).to eq("NO_SEATS_SELECTED")
      end

      it "returns error if seat count exceeds max purchase limit" do
        excessive_seats = (1..7).to_a
        result = subject.call(excessive_seats)
        expect(result[:success]).to be false
        expect(result[:code]).to eq("MAX_PURCHASE_EXCEEDED")
      end

      it "returns error if seats do not belong to the showtime" do
        other_venue = Venue.create!(name: "Other", grid_rows: 1, grid_cols: 1)
        other_seat = Seat.create!(venue: other_venue, grid_row: 1, grid_col: 1)

        result = subject.call([other_seat.id])
        expect(result[:success]).to be false
        expect(result[:code]).to eq("INVALID_SEAT_SELECTION")
      end
    end

    context "successful initiation" do
      it "holds seats, marks them processing, stores context, and enqueues job" do
        seat_ids = [seat1.id, seat2.id]

        expect(hold_service).to receive(:hold!).with(seat_ids, bypass_limit: true, refresh: true)
        expect(PaymentSimulationJob).to receive(:perform_later).with(kind_of(String), user.id, showtime.id)

        result = subject.call(seat_ids)

        expect(result[:success]).to be true
        expect(result[:status]).to eq(:processing)
        expect(result[:payment_reference]).to be_present

        expect(ss1.reload.status).to eq("processing")
        expect(ss2.reload.status).to eq("processing")

        ctx_json = REDIS_POOL.with { |c| c.get("payment_ctx:#{result[:payment_reference]}") }
        ctx = JSON.parse(ctx_json)
        expect(ctx['seat_ids']).to match_array(seat_ids)
      end
    end

    context "when hold acquisition fails" do
      it "fails if the refresh hold attempt fails" do
        allow(hold_service).to receive(:hold!).with(
          [seat1.id],
          bypass_limit: true,
          refresh: true
        ).and_return({ success: false, code: "SEAT_TAKEN", message: "Could not secure all selected seats" })

        result = subject.call([seat1.id])

        expect(result[:success]).to be false
        expect(result[:message]).to include("Could not secure all selected seats")
        expect(PaymentSimulationJob).not_to have_received(:perform_later)
        expect(ss1.reload.status).to eq("available")
      end
    end

    context "idempotency" do
      let(:key) { "idem_key_1" }

      it "returns completed status if order already exists" do
        order = Order.create!(user: user, showtime: showtime, status: :paid, total_amount_cents: 1000)
        Payment.create!(order: order, status: :successful, amount_cents: 1000, idempotency_key: key)

        result = subject.call([seat1.id], idempotency_key: key)

        expect(result[:success]).to be true
        expect(result[:status]).to eq(:completed)
        expect(result[:order_id]).to eq(order.id)

        expect(PaymentSimulationJob).not_to have_received(:perform_later)
      end

      it "returns processing status if payment is currently processing" do
        REDIS_POOL.with { |c| c.set("idempotency:#{key}", "processing") }

        result = subject.call([seat1.id], idempotency_key: key)

        expect(result[:success]).to be true
        expect(result[:status]).to eq(:processing)
        expect(result[:message]).to eq("Payment is already processing.")

        expect(PaymentSimulationJob).not_to have_received(:perform_later)
      end

      it "marks idempotency key as processing for new requests" do
        result = subject.call([seat1.id], idempotency_key: key)

        expect(result[:success]).to be true
        status = REDIS_POOL.with { |c| c.get("idempotency:#{key}") }
        expect(status).to eq("processing")
      end
    end

    context "locking failures" do
      it "returns error if seats cannot be locked (LockWaitTimeout)" do
        allow_any_instance_of(ActiveRecord::Relation)
          .to receive(:lock)
          .with("FOR UPDATE NOWAIT")
          .and_raise(ActiveRecord::LockWaitTimeout)

        result = subject.call([seat1.id])

        expect(result[:success]).to be false
        expect(result[:code]).to eq("SEAT_LOCKED")
        expect(hold_service).to have_received(:release!).with([seat1.id])
      end

      it "returns error if seat is no longer available" do
        order = Order.create!(user: user, showtime: showtime, status: :paid, total_amount_cents: 1000)
        ss1.update!(status: :sold, order: order)

        result = subject.call([seat1.id])

        expect(result[:success]).to be false
        expect(result[:code]).to eq("SEAT_NO_LONGER_AVAILABLE")
        expect(hold_service).to have_received(:release!).with([seat1.id])
      end
    end
  end
end
