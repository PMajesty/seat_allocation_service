require 'rails_helper'

RSpec.describe "Api::V1::Checkouts", type: :request do
  let(:user) { User.create!(email: "api_checkout@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "ApiVenue", grid_rows: 2, grid_cols: 5) }
  let(:event) { Event.create!(title: "ApiEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }

  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }

  let(:checkout_starter) { instance_double(CheckoutStarter) }

  before do
    allow(CheckoutStarter).to receive(:new).and_return(checkout_starter)
  end

  describe "POST /api/v1/showtimes/:id/checkout" do
    context "when authenticated" do
      let(:headers) { jwt_headers(user) }

      it "returns accepted when checkout starts processing" do
        allow(checkout_starter).to receive(:call)
          .with([seat.id], idempotency_key: kind_of(String))
          .and_return({ success: true, status: :processing, payment_reference: "ref_123" })

        post checkout_api_v1_showtime_path(showtime),
             params: { seat_ids: [seat.id] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:accepted)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["status"]).to eq("processing")
        expect(json["payment_reference"]).to eq("ref_123")
        expect(json["message"]).to eq("Payment is being processed.")
      end

      it "returns ok when checkout is already completed (idempotency)" do
        allow(checkout_starter).to receive(:call)
          .with([seat.id], idempotency_key: kind_of(String))
          .and_return({ success: true, status: :completed, order_id: 456 })

        post checkout_api_v1_showtime_path(showtime),
             params: { seat_ids: [seat.id] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["order_id"]).to eq(456)
      end

      it "returns unprocessable_entity when checkout fails to start" do
        allow(checkout_starter).to receive(:call)
          .with([seat.id], idempotency_key: kind_of(String))
          .and_return({ success: false, message: 'No seats selected', code: 'NO_SEATS_SELECTED' })

        post checkout_api_v1_showtime_path(showtime),
             params: { seat_ids: [seat.id] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq('No seats selected')
      end

      context "Purchase Limits" do
        it "rejects requests exceeding the max purchase limit" do
          seats = (1..7).map { |i| Seat.create!(venue: venue, grid_row: 2, grid_col: i) }
          seats.each { |s| ShowtimeSeat.create!(showtime: showtime, seat: s, price_cents: 1000) }
          seat_ids = seats.map(&:id)

          allow(checkout_starter).to receive(:call)
            .with(seat_ids, idempotency_key: kind_of(String))
            .and_return({ success: false, message: "Cannot purchase more than 6 seats per order." })

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: seat_ids },
               headers: headers,
               as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json["message"]).to include("Cannot purchase more than 6 seats")
        end
      end

      context "Idempotency" do
        it "passes idempotency key from headers to service" do
          key = "uniq_123"
          allow(checkout_starter).to receive(:call)
            .with([seat.id], idempotency_key: key)
            .and_return({ success: true, status: :processing, payment_reference: "ref_999" })

          post checkout_api_v1_showtime_path(showtime),
               params: { seat_ids: [seat.id] },
               headers: headers.merge('Idempotency-Key' => key),
               as: :json

          expect(response).to have_http_status(:accepted)
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
