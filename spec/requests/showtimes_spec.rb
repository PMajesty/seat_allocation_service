require 'rails_helper'

RSpec.describe "Showtimes", type: :request do
  let(:user) { User.create!(email: "show@example.com", password: "password123") }
  let(:venue) { Venue.create!(name: "Theater", grid_rows: 5, grid_cols: 5) }
  let(:event) { Event.create!(title: "Play", base_price_cents: 5000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.week.from_now) }

  describe "GET /showtimes/:id" do
    context "when logged in" do
      let(:token) { JwtService.encode(user_id: user.id, ver: user.token_version) }
      let(:headers) { { "Authorization" => "Bearer #{token}" } }

      it "renders the showtime page" do
        get showtime_path(showtime), headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(event.title)
        expect(response.body).to include(venue.name)
        expect(response.body).to include("seat-selection-app")
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get showtime_path(showtime)
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
