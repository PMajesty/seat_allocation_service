require 'rails_helper'

RSpec.describe "Home", type: :request do
  describe "GET /" do
    let!(:event) { Event.create!(title: "Concert", base_price_cents: 1000, active: true) }
    let!(:venue) { Venue.create!(name: "Hall", grid_rows: 1, grid_cols: 1) }
    let!(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }

    before do
      Event.__elasticsearch__.create_index!(force: true)
      Event.import(refresh: true)
    end

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

    describe "Search" do
      let(:search_term) { "Concert" }

      it "filters events using the search parameter" do
        get root_path, params: { q: search_term }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Concert")
      end

      context "when no events match" do
        it "displays the empty state message" do
          get root_path, params: { q: "Missing" }

          expect(response.body).to include('No events found matching "Missing"')
          expect(response.body).to include("Clear search")
        end
      end

      context "when Elasticsearch is down" do
        before do
          allow(Event).to receive(:search_events).and_raise(Faraday::ConnectionFailed.new("Connection refused"))
        end

        it "handles the error gracefully without crashing" do
          expect(Rails.error).to receive(:report).with(instance_of(Faraday::ConnectionFailed), hash_including(handled: true, severity: :warning))

          get root_path, params: { q: "Crash" }

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Search is currently under maintenance")
          expect(response.body).not_to include("Internal Server Error")
        end
      end
    end

    describe "Pagination" do
      before do
        25.times do |i|
          Event.create!(
            title: "Extra Event #{i}",
            base_price_cents: 1000,
            active: true
          )
        end
        Event.import(refresh: true)
      end

      it "paginates the events list (page 1)" do
        get root_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("pagination-wrapper")
        expect(response.body.scan(/class="event-card"/).size).to eq(10)
      end

      it "allows navigating to subsequent pages (page 2)" do
        get root_path, params: { page: 2 }

        expect(response).to have_http_status(:ok)
        expect(response.body.scan(/class="event-card"/).size).to eq(10)
      end

      it "shows remaining items on the last page (page 3)" do
        get root_path, params: { page: 3 }

        expect(response).to have_http_status(:ok)
        expect(response.body.scan(/class="event-card"/).size).to eq(6)
      end
    end
  end
end
