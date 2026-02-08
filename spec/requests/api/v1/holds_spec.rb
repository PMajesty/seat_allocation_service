require 'rails_helper'

RSpec.describe "Api::V1::Holds", type: :request do
  let(:user) { User.create!(email: "api@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "ApiVenue", grid_rows: 2, grid_cols: 2) }
  let(:event) { Event.create!(title: "ApiEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let!(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000) }

  let(:hold_service) { instance_double(HoldService) }

  before do
    allow(HoldService).to receive(:new).and_return(hold_service)
  end

  describe "POST /api/v1/showtimes/:id/holds" do
    context "when authenticated" do
      let(:headers) { jwt_headers(user) }

      it "creates a hold successfully" do
        allow(hold_service).to receive(:hold!).with([seat.id]).and_return({ success: true, held_seat_ids: [seat.id] })

        post holds_api_v1_showtime_path(showtime), params: { seat_ids: [seat.id] }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["held_seat_ids"]).to include(seat.id)
      end

      it "returns error when hold fails" do
        allow(hold_service).to receive(:hold!).with([seat.id]).and_return({
          success: false,
          code: "SEAT_TAKEN",
          message: "One or more selected seats are no longer available."
        })

        post holds_api_v1_showtime_path(showtime), params: { seat_ids: [seat.id] }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["code"]).to eq("SEAT_TAKEN")
        expect(json["message"]).to be_present
      end

      it "returns error when no seats selected" do
        allow(hold_service).to receive(:hold!).with([]).and_return({
          success: false,
          code: "NO_SEATS_SELECTED",
          message: "No seats selected"
        })

        post holds_api_v1_showtime_path(showtime), params: { seat_ids: [] }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when unauthenticated" do
      it "returns unauthorized" do
        post holds_api_v1_showtime_path(showtime), params: { seat_ids: [seat.id] }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "DELETE /api/v1/showtimes/:id/holds" do
    context "when authenticated" do
      let(:headers) { jwt_headers(user) }

      it "releases a hold" do
        allow(hold_service).to receive(:release!).with([seat.id]).and_return({ success: true })

        delete holds_api_v1_showtime_path(showtime), params: { seat_ids: [seat.id] }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end
    end
  end
end
