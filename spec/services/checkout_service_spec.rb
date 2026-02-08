require 'rails_helper'

RSpec.describe CheckoutService, redis: true do
  let(:user) { User.create!(email: "checkout@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "CheckoutVenue", grid_rows: 2, grid_cols: 2) }
  let(:event) { Event.create!(title: "CheckoutEvent", base_price_cents: 1000) }
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

    allow(subject).to receive(:sleep)
    allow(subject).to receive(:rand).and_return(0.9)

    REDIS_POOL.with do |conn|
      conn.set("seat_hold:#{showtime.id}:#{seat1.id}", user.id.to_s)
      conn.set("seat_hold:#{showtime.id}:#{seat2.id}", user.id.to_s)
    end
  end

  describe "#call" do
    context "when input is invalid" do
      it "returns error if seat_ids is empty" do
        result = subject.call([])
        expect(result[:success]).to be false
        expect(result[:message]).to eq("No seats selected")
      end
    end

    context "when seats are held by the user" do
      it "creates an order and tickets successfully" do
        expect {
          result = subject.call([seat1.id, seat2.id])
          expect(result[:success]).to be true
          expect(result[:order_id]).to be_present
        }.to change(Order, :count).by(1)
         .and change(Ticket, :count).by(2)

        order = Order.last
        expect(order.user).to eq(user)
        expect(order.total_amount_cents).to eq(2000)
        expect(order.status).to eq("paid")

        expect(ss1.reload.status).to eq("sold")
        expect(ss2.reload.status).to eq("sold")
        expect(ss1.order).to eq(order)
      end

      it "releases redis holds after successful purchase" do
        subject.call([seat1.id])
        expect(hold_service).to have_received(:release!).with([seat1.id])
      end
    end

    context "hold refreshing logic" do
      before do
        REDIS_POOL.with { |c| c.del("seat_hold:#{showtime.id}:#{seat2.id}") }
      end

      it "refreshes holds for ALL seats with refresh: true" do
        subject.call([seat1.id, seat2.id])
        expect(hold_service).to have_received(:hold!).with(
          [seat1.id, seat2.id],
          bypass_limit: true,
          refresh: true
        )
      end

      it "fails if the refresh hold attempt fails" do
        allow(hold_service).to receive(:hold!).with(
          [seat1.id, seat2.id],
          bypass_limit: true,
          refresh: true
        ).and_return({ success: false, code: "SEAT_TAKEN", message: "Could not secure all selected seats" })

        result = subject.call([seat1.id, seat2.id])
        expect(result[:success]).to be false
        expect(result[:message]).to include("Could not secure all selected seats")

        expect(Order.count).to eq(0)
      end
    end

    context "Race Condition / TTL Expiry Handling" do
      it "ensures holds are refreshed BEFORE payment latency begins" do
        expect(hold_service).to receive(:hold!).with(anything, hash_including(refresh: true)).ordered
        expect(subject).to receive(:sleep).with(5.0).ordered

        subject.call([seat1.id])
      end

      it "simulates a scenario where hold expires in 1s, but checkout refreshes it" do
        subject.call([seat1.id])

        expect(hold_service).to have_received(:hold!).with(
          [seat1.id],
          bypass_limit: true,
          refresh: true
        )
      end
    end

    context "payment simulation" do
      it "fails when payment fails randomly" do
        allow(subject).to receive(:rand).and_return(0.09)

        result = subject.call([seat1.id])
        expect(result[:success]).to be false
        expect(result[:message]).to include('Payment failed (Simulated). Please try again.')

        expect(Order.count).to eq(0)
        expect(ss1.reload.status).to eq("available")

        expect(hold_service).to have_received(:release!)
      end

      it "succeeds when payment succeeds" do
        allow(subject).to receive(:rand).and_return(0.8)

        result = subject.call([seat1.id])
        expect(result[:success]).to be true
      end

      it "returns a specific simulation message on failure" do
        allow(subject).to receive(:rand).and_return(0.09)
        result = subject.call([seat1.id])
        expect(result[:message]).to include("Simulated")
      end
    end

    context "database race conditions" do
      it "fails if a seat is already sold in DB despite Redis hold" do
        other_order = Order.create!(user: user, showtime: showtime, total_amount_cents: 1000, status: :paid)
        ss1.update!(status: :sold, order: other_order)

        result = subject.call([seat1.id])
        expect(result[:success]).to be false
        expect(result[:message]).to include("One or more seats are no longer available")

        expect(hold_service).to have_received(:release!).with([seat1.id])
      end

      it "fails fast if the DB lock cannot be acquired immediately (NOWAIT)" do
        allow_any_instance_of(ActiveRecord::Relation)
          .to receive(:lock)
          .with("FOR UPDATE NOWAIT")
          .and_raise(ActiveRecord::LockWaitTimeout)

        result = subject.call([seat1.id])

        expect(result[:success]).to be false
        expect(result[:code]).to eq("SEAT_LOCKED")
        expect(result[:message]).to eq("Seats are currently being processed by another user.")

        expect(hold_service).to have_received(:release!).with([seat1.id])
      end
    end

    context "unexpected errors" do
      it "handles exceptions gracefully" do
        allow(Order).to receive(:create!).and_raise(StandardError.new("Boom"))

        result = subject.call([seat1.id])
        expect(result[:success]).to be false
        expect(result[:message]).to eq("An unexpected error occurred during processing.")

        expect(hold_service).to have_received(:release!).with([seat1.id])
      end
    end

    context "idempotency" do
      let(:idempotency_key) { "idem_key_unique_123" }

      it "creates a payment record with the idempotency key on success" do
        expect {
          subject.call([seat1.id], idempotency_key: idempotency_key)
        }.to change(Payment, :count).by(1)

        payment = Payment.last
        expect(payment.idempotency_key).to eq(idempotency_key)
        expect(payment.status).to eq("successful")
      end

      it "returns the existing order if the idempotency key was already processed" do
        existing_order = Order.create!(
          user: user,
          showtime: showtime,
          status: :paid,
          total_amount_cents: 1000,
          currency: "USD"
        )
        Payment.create!(
          order: existing_order,
          status: :successful,
          amount_cents: 1000,
          currency: "USD",
          idempotency_key: idempotency_key
        )

        result = nil
        expect {
          result = subject.call([seat1.id], idempotency_key: idempotency_key)
        }.not_to change(Order, :count)

        expect(result[:success]).to be true
        expect(result[:order_id]).to eq(existing_order.id)
      end

      it "processes a new order if the key is different" do
        subject.call([seat1.id], idempotency_key: "key_1")

        expect {
          subject.call([seat2.id], idempotency_key: "key_2")
        }.to change(Order, :count).by(1)
      end
    end

    context "when redis cleanup fails after successful purchase" do
      it "logs error and returns success (best effort)" do
        allow(hold_service).to receive(:release!).with([seat1.id]).and_raise(StandardError.new("Redis connection failed"))
        allow(Rails.logger).to receive(:error)

        result = subject.call([seat1.id])

        expect(result[:success]).to be true
        expect(result[:order_id]).to be_present
        expect(Order.count).to eq(1)
        expect(Rails.logger).to have_received(:error).with(/Redis cleanup failed for Order/)
      end
    end
  end
end
