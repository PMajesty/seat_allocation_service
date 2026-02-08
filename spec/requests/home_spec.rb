require 'rails_helper'

RSpec.describe "Home", type: :request do
  describe "GET /" do
    let!(:event) { Event.create!(title: "Concert", base_price_cents: 1000, active: true) }
    let!(:venue) { Venue.create!(name: "Hall", grid_rows: 1, grid_cols: 1) }
    let!(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }

    it "renders the home page with events" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Concert")
      expect(response.body).to include("Upcoming Events")
    end

    it "displays scheduled showtimes" do
      get root_path
      expect(response.body).to include(showtime.starts_at.strftime("%b %d"))
    end
  end
end
