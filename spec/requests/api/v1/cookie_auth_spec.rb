require 'rails_helper'

RSpec.describe "API Cookie Authentication", type: :request do
  let(:venue) { Venue.create!(name: "Venue", grid_rows: 5, grid_cols: 5) }
  let(:event) { Event.create!(title: "Event", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:user) { User.create!(email: "cookie_auth@test.com", password: "password123") }
  let(:token) { JwtService.encode(user_id: user.id, ver: user.token_version) }

  describe "GET /api/v1/showtimes/:id/seats" do
    context "when authenticated via HttpOnly cookie" do
      it "allows access and returns 200 OK with composite data" do
        get "/api/v1/showtimes/#{showtime.id}/seats", headers: { "Cookie" => "jwt=#{token}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to include("public_grid_json", "user_context")
      end
    end

    context "when cookie is missing" do
      it "returns 401 Unauthorized" do
        get "/api/v1/showtimes/#{showtime.id}/seats"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated via Authorization header (API Client)" do
      it "allows access and returns 200 OK" do
        get "/api/v1/showtimes/#{showtime.id}/seats", headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
