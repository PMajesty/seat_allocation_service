require 'rails_helper'

RSpec.describe "Api::V1::Checkouts", type: :request do
  let(:user) { User.create!(email: "api_checkout@example.com", password: "password123") }
  let(:other_user) { User.create!(email: "other@example.com", password: "password123") }

  let(:venue) { Venue.create!(name: "ApiVenue", grid_rows: 2, grid_cols: 5) }
  let(:event) { Event.create!(title: "ApiEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }

  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let(:seat_other) { Seat.create!(venue: venue, grid_row: 1, grid_col: 2) }
  let!(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000) }
  let!(:showtime_seat_other) { ShowtimeSeat.create!(showtime: showtime, seat: seat_other, price_cents: 1000) }

  let(:checkout_service) { instance_double(CheckoutService) }

  before do
    allow(CheckoutService).to receive(:new).and_return(checkout_service)
  end

  describe "POST /api/v1/showtimes/:id/checkout" do
    context "when authenticated" do
      let(:headers) { jwt_headers(user) }

      it "returns success when checkout succeeds" do
        allow(checkout_service).to receive(:call)
          .with([seat.id], idempotency_key: kind_of(String))
          .and_return({ success: true, order_id: 123 })

        post checkout_api_v1_showtime_path(showtime),
             params: { seat_ids: [seat.id] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["order_id"]).to eq(123)
      end

      it "returns unprocessable_content when checkout fails" do
        allow(checkout_service).to receive(:call)
          .with([seat.id], idempotency_key: kind_of(String))
          .and_return({ success: false, message: 'Payment failed (Simulated). Please try again.' })

        post checkout_api_v1_showtime_path(showtime),
             params: { seat_ids: [seat.id] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq('Payment failed (Simulated). Please try again.')
      end

      it "handles empty seat_ids gracefully" do
        allow(checkout_service).to receive(:call)
          .with([], idempotency_key: kind_of(String))
          .and_return({ success: false, message: "No seats selected" })

        post checkout_api_v1_showtime_path(showtime),
             params: { seat_ids: [] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      context "Purchase Limits" do
        it "rejects requests exceeding the max purchase limit" do
          seats = (1..7).map { |i| Seat.create!(venue: venue, grid_row: 2, grid_col: i) }
          seats.each { |s| ShowtimeSeat.create!(showtime: showtime, seat: s, price_cents: 1000) }
          seat_ids = seats.map(&:id)


          allow(checkout_service).to receive(:call)
            .with(seat_ids, idempotency_key: kind_of(String))
            .and_return({ success: false, message: "Cannot purchase more than 6 seats per order." })

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: seat_ids },
               headers: headers,
               as: :json

          expect(response).to have_http_status(:unprocessable_content)
          json = JSON.parse(response.body)
          expect(json["message"]).to include("Cannot purchase more than 6 seats")
        end
      end

      context "Idempotency" do
        it "passes idempotency key from headers to service" do
          key = "uniq_123"
          allow(checkout_service).to receive(:call)
            .with([seat.id], idempotency_key: key)
            .and_return({ success: true, order_id: 999 })

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: [seat.id] },
               headers: headers.merge('Idempotency-Key' => key),
               as: :json

          expect(response).to have_http_status(:ok)
        end

        it "generates an unguessable key if none is provided" do
          generated_key = "generated-uuid-123"
          allow(SecureRandom).to receive(:uuid).and_return(generated_key)

          allow(checkout_service).to receive(:call)
            .with([seat.id], idempotency_key: generated_key)
            .and_return({ success: true, order_id: 999 })

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: [seat.id] },
               headers: headers,
               as: :json

          expect(response).to have_http_status(:ok)
        end

        it "handles DB uniqueness race condition gracefully (recovers existing order)" do
          allow(CheckoutService).to receive(:new).and_call_original

          hold_service = instance_double(HoldService)
          allow(HoldService).to receive(:new).and_return(hold_service)
          allow(hold_service).to receive(:hold!).and_return({ success: true })
          allow(hold_service).to receive(:release!)

          allow_any_instance_of(CheckoutService).to receive(:simulate_payment_latency)
          allow_any_instance_of(CheckoutService).to receive(:payment_failure?).and_return(false)

          key = "race_condition_key"

          allow(Payment).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

          found_order = instance_double(Order, user_id: user.id, id: 777)
          found_payment = instance_double(Payment, order: found_order, order_id: 777)
          allow(Payment).to receive(:find_by).with(idempotency_key: key, status: :successful).and_return(found_payment)

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: [seat.id] },
               headers: headers.merge('Idempotency-Key' => key),
               as: :json

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
          expect(json["order_id"]).to eq(777)
        end

        it "returns error when DB uniqueness race condition is not recoverable" do
          allow(CheckoutService).to receive(:new).and_call_original

          hold_service = instance_double(HoldService)
          allow(HoldService).to receive(:new).and_return(hold_service)
          allow(hold_service).to receive(:hold!).and_return({ success: true })
          allow(hold_service).to receive(:release!)

          allow_any_instance_of(CheckoutService).to receive(:simulate_payment_latency)
          allow_any_instance_of(CheckoutService).to receive(:payment_failure?).and_return(false)

          key = "race_fail_key"

          allow(Payment).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

          allow(Payment).to receive(:find_by).with(idempotency_key: key, status: :successful).and_return(nil)

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: [seat.id] },
               headers: headers.merge('Idempotency-Key' => key),
               as: :json

          expect(response).to have_http_status(:unprocessable_content)
          json = JSON.parse(response.body)
          expect(json["success"]).to be false
          expect(json["message"]).to eq("This seat has already been paid for.")
        end
      end
    end

    context "when unauthenticated" do
      it "returns unauthorized" do
        post checkout_api_v1_showtime_path(showtime), params: { seat_ids: [seat.id] }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
