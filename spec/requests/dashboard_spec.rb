require 'rails_helper'

RSpec.describe "Dashboard", type: :request, redis: true do
  let(:user) { User.create!(email: "dash@example.com", password: "password123", role: :visitor) }
  let(:admin) { User.create!(email: "admin@example.com", password: "password123", role: :admin) }

  let(:other_user) { User.create!(email: "other@example.com", password: "password123") }

  let(:venue) { Venue.create!(name: "DashVenue", grid_rows: 1, grid_cols: 1) }
  let(:event) { Event.create!(title: "DashEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }

  let(:other_order) { Order.create!(user: other_user, showtime: showtime, total_amount_cents: 1000, status: :paid) }
  let!(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000, status: :sold, order: other_order) }

  before do
    REDIS_POOL.with { |c| c.set("simulation_mode", "off") }
  end

  describe "GET /dashboard" do
    context "when logged in" do
      let(:token) { JwtService.encode(user_id: user.id, ver: user.token_version) }
      let(:headers) { { "Authorization" => "Bearer #{token}" } }

      it "renders the dashboard" do
        get dashboard_path, headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("My Account")
        expect(response.body).to include(user.email)
      end

      it "displays purchased tickets" do
        order = Order.create!(user: user, showtime: showtime, total_amount_cents: 1000, status: :paid)
        ticket = Ticket.create!(order: order, showtime_seat: showtime_seat, code: "TICKET123")
        showtime_seat.update!(order: order)

        get dashboard_path, headers: headers

        expect(response.body).to include("My Tickets")
        expect(response.body).to include(event.title)
        expect(response.body).to include("TICKET123")
        expect(response.body).to include("Paid")
      end

      it "shows empty state when no tickets purchased" do
        get dashboard_path, headers: headers
        expect(response.body).to include("You haven't purchased any tickets yet")
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get dashboard_path
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq("Please log in to continue.")
      end
    end

    context "role visibility" do
      it "does not show role to visitor" do
        token = JwtService.encode(user_id: user.id, ver: user.token_version)
        headers = { "Authorization" => "Bearer #{token}" }

        get dashboard_path, headers: headers
        expect(response.body).not_to include("Role:")
      end

      it "shows role to admin" do
        token = JwtService.encode(user_id: admin.id, ver: admin.token_version)
        headers = { "Authorization" => "Bearer #{token}" }

        get dashboard_path, headers: headers
        expect(response.body).to include("Role:")
        expect(response.body).to include("Admin")
      end
    end

    context "simulation breaker" do
      it "is visible to admin" do
        token = JwtService.encode(user_id: admin.id, ver: admin.token_version)
        headers = { "Authorization" => "Bearer #{token}" }

        get dashboard_path, headers: headers
        expect(response.body).to include("Load Simulation Breaker")
      end

      it "is hidden from visitor" do
        token = JwtService.encode(user_id: user.id, ver: user.token_version)
        headers = { "Authorization" => "Bearer #{token}" }

        get dashboard_path, headers: headers
        expect(response.body).not_to include("Load Simulation Breaker")
      end
    end
  end

  describe "POST /dashboard/simulation" do
    context "as admin" do
      let(:token) { JwtService.encode(user_id: admin.id, ver: admin.token_version) }
      let(:headers) { { "Authorization" => "Bearer #{token}" } }

      it "updates simulation mode" do
        expect(LoadSimulationService).to receive(:set_mode).with("high")
        post dashboard_simulation_path, params: { mode: "high" }, headers: headers
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:notice]).to include("high")
      end
    end

    context "as visitor" do
      let(:token) { JwtService.encode(user_id: user.id, ver: user.token_version) }
      let(:headers) { { "Authorization" => "Bearer #{token}" } }

      it "does not update simulation mode" do
        expect(LoadSimulationService).not_to receive(:set_mode)
        post dashboard_simulation_path, params: { mode: "high" }, headers: headers
      end
    end
  end
end
