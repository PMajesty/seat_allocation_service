require 'rails_helper'

RSpec.describe CheckoutCallbackHandler, redis: true do
  let(:user) { User.create!(email: "callback@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "CallbackVenue", grid_rows: 2, grid_cols: 2) }
  let(:event) { Event.create!(title: "CallbackEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat1) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }

  let!(:ss1) { ShowtimeSeat.create!(showtime: showtime, seat: seat1, price_cents: 1000, status: :processing) }

  let(:hold_service) { instance_double(HoldService) }
  let(:payment_ref) { SecureRandom.uuid }
  let(:idempotency_key) { "idem_key_callback" }
  let(:seat_ids) { [seat1.id] }

  subject { described_class.new(user, showtime.id) }

  before do
    allow(HoldService).to receive(:new).with(user, showtime.id).and_return(hold_service)
    allow(hold_service).to receive(:release!)

    allow(ActionCable.server).to receive(:broadcast)
    allow(Rails.logger).to receive(:error)

    data = { seat_ids: seat_ids, idempotency_key: idempotency_key }
    REDIS_POOL.with { |c| c.set("payment_ctx:#{payment_ref}", data.to_json) }
  end

  describe "#call" do
    let(:gateway_response) do
      { transaction_id: "tx_123", timestamp: Time.current.iso8601, status: 'approved' }
    end

    context "when payment is successful" do
      it "creates order, payment, tickets and broadcasts success" do
        expect {
          subject.call(payment_ref, true, gateway_response)
        }.to change(Order, :count).by(1)
         .and change(Ticket, :count).by(1)
         .and change(Payment, :count).by(1)

        order = Order.last
        expect(order.status).to eq("paid")
        expect(order.total_amount_cents).to eq(1000)
        expect(ss1.reload.status).to eq("sold")

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'success', order_id: order.id, payment_reference: payment_ref)
        )

        expect(hold_service).to have_received(:release!).with(seat_ids)

        key_exists = REDIS_POOL.with { |c| c.exists("idempotency:#{idempotency_key}") }
        expect(key_exists).to eq(0)
      end

      it "clears failure counter on success" do
        REDIS_POOL.with { |c| c.set("payment_failures:#{user.id}", "1") }

        subject.call(payment_ref, true, gateway_response)

        count = REDIS_POOL.with { |c| c.get("payment_failures:#{user.id}") }
        expect(count).to be_nil
      end

      it "handles race condition where order was already created by another thread" do
        existing_order = Order.create!(user: user, showtime: showtime, status: :paid, total_amount_cents: 1000)
        Payment.create!(order: existing_order, status: :successful, amount_cents: 1000, idempotency_key: idempotency_key)

        allow(Payment).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        subject.call(payment_ref, true, gateway_response)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'success', order_id: existing_order.id)
        )
      end

      it "fails if seats are not in processing state (e.g. timed out)" do
        ss1.update!(status: :available)

        subject.call(payment_ref, true, gateway_response)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'error', code: 'INTERNAL_ERROR')
        )
        expect(Order.count).to eq(0)
      end

      context "when redis cleanup fails" do
        it "logs error and returns success (best effort)" do
          allow(hold_service).to receive(:release!).with(seat_ids).and_raise(StandardError.new("Redis connection failed"))

          subject.call(payment_ref, true, gateway_response)

          expect(Order.count).to eq(1)
          expect(Rails.logger).to have_received(:error).with(/Redis cleanup failed for Order/)

          expect(ActionCable.server).to have_received(:broadcast).with(
            "user_payment:#{user.id}",
            hash_including(status: 'success')
          )
        end
      end

      context "when a concurrent worker holds the lock (LockWaitTimeout)" do
        before do
          relation = instance_double(ActiveRecord::Relation)
          allow(ShowtimeSeat).to receive(:where).and_return(relation)
          allow(relation).to receive(:lock).with("FOR UPDATE NOWAIT").and_raise(ActiveRecord::LockWaitTimeout)
          allow(relation).to receive(:index_by).and_raise(ActiveRecord::LockWaitTimeout)
        end

        it "returns silently without reverting seats or broadcasting failure" do
          subject.call(payment_ref, true, gateway_response)

          expect(ActionCable.server).not_to have_received(:broadcast).with(
            "user_payment:#{user.id}",
            hash_including(status: 'error')
          )

          expect(ActionCable.server).not_to have_received(:broadcast).with(
            "user_payment:#{user.id}",
            hash_including(status: 'success')
          )

          expect(ss1.reload.status).to eq("processing")

          expect(hold_service).not_to have_received(:release!)
        end
      end
    end

    context "when payment fails" do
      it "reverts seats, releases holds, and broadcasts failure" do
        subject.call(payment_ref, false, { error_code: 'card_declined' })

        expect(ss1.reload.status).to eq("available")
        expect(hold_service).to have_received(:release!).with(seat_ids)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'error', code: 'PAYMENT_FAILED')
        )
      end

      it "increments failure counter but does not lock out on first failure" do
        subject.call(payment_ref, false, {})

        count = REDIS_POOL.with { |c| c.get("payment_failures:#{user.id}") }
        expect(count).to eq("1")

        lockout = REDIS_POOL.with { |c| c.get("checkout_lockout:#{user.id}") }
        expect(lockout).to be_nil
      end

      it "locks user out after 2 failures" do
        subject.call(payment_ref, false, {})
        subject.call(payment_ref, false, {})

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'error', code: 'PAYMENT_LOCKOUT')
        )

        lockout = REDIS_POOL.with { |c| c.get("checkout_lockout:#{user.id}") }
        expect(lockout).to eq("1")
      end
    end

    context "unexpected errors" do
      it "handles exceptions gracefully during order creation" do
        allow(Order).to receive(:create!).and_raise(StandardError.new("Boom"))

        subject.call(payment_ref, true, gateway_response)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'error', code: 'INTERNAL_ERROR')
        )

        expect(hold_service).to have_received(:release!).with(seat_ids)
        expect(ss1.reload.status).to eq("available")
      end
    end

    context "missing context" do
      it "broadcasts session expired error" do
        REDIS_POOL.with { |c| c.del("payment_ctx:#{payment_ref}") }

        subject.call(payment_ref, true, gateway_response)

        expect(ActionCable.server).to have_received(:broadcast).with(
          "user_payment:#{user.id}",
          hash_including(status: 'error', code: 'SESSION_EXPIRED')
        )
      end
    end
  end
end
