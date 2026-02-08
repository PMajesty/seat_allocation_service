require 'rails_helper'

RSpec.describe "Api::V1::Showtimes", type: :request do
  let(:user) { User.create!(email: "api_show@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "Venue", grid_rows: 1, grid_cols: 1) }
  let(:event) { Event.create!(title: "Event", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let!(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000, status: :available) }

  let(:inventory_service) { instance_double(ShowtimeInventoryService) }

  before do
    allow(ShowtimeInventoryService).to receive(:new).with(showtime.id.to_s, anything).and_return(inventory_service)
  end

  describe "GET /api/v1/showtimes/:id/seats" do
    context "when authenticated" do
      let(:headers) { jwt_headers(user) }

      it "returns the seat inventory" do
        allow(inventory_service).to receive(:call).and_return([
          { id: seat.id, row: 1, col: 1, status: "available", price: 1000, type: "Standard" }
        ])

        get seats_api_v1_showtime_path(showtime), headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.first["id"]).to eq(seat.id)
        expect(json.first["status"]).to eq("available")
      end
    end

    context "when unauthenticated" do
      it "returns unauthorized" do
        allow(inventory_service).to receive(:call).and_return([])

        get seats_api_v1_showtime_path(showtime), as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
