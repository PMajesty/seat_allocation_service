require 'rails_helper'

RSpec.describe SimulationJob, type: :job, redis: true do
  include ActiveJob::TestHelper

  let(:venue) { Venue.create!(name: "SimVenue", grid_rows: 2, grid_cols: 2) }
  let(:event) { Event.create!(title: "SimEvent", base_price_cents: 1000) }
  let!(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now, status: :scheduled) }
  let!(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let!(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000) }

  before do
    modes = Array.new(20, "real") + ["off"]
    allow(LoadSimulationService).to receive(:current_mode).and_return(*modes)

    allow_any_instance_of(SimulationJob).to receive(:sleep)
    allow_any_instance_of(SimulationJob).to receive(:cleanup_users)
    allow_any_instance_of(SimulationJob).to receive(:filter_active_showtimes).and_return([showtime.id])
  end

  it "creates a simulation user" do
    expect {
      perform_enqueued_jobs { described_class.perform_later }
    }.to change(User, :count).by_at_least(1)

    user = User.last
    expect(user.email).to include("@simulation.local")
  end

  it "attempts to hold seats" do
    hold_service = instance_double(HoldService)
    allow(HoldService).to receive(:new).and_return(hold_service)
    allow(hold_service).to receive(:hold!).and_return({ success: true })
    allow(hold_service).to receive(:release!)

    inventory_data = [{ id: seat.id, status: "available", price: 1000 }]
    service_response = { public_grid_json: inventory_data.to_json }

    allow_any_instance_of(ShowtimeInventoryService).to receive(:call).and_return(service_response)

    perform_enqueued_jobs { described_class.perform_later }

    expect(hold_service).to have_received(:hold!).at_least(:once)
  end

  context "when mode is bot" do
    before do
      modes = Array.new(10, "bot") + ["off"]
      allow(LoadSimulationService).to receive(:current_mode).and_return(*modes)
    end

    it "creates untrusted users" do
      inventory_data = [{ id: seat.id, status: "available", price: 1000 }]
      service_response = { public_grid_json: inventory_data.to_json }

      allow_any_instance_of(ShowtimeInventoryService).to receive(:call).and_return(service_response)

      allow_any_instance_of(HoldService).to receive(:hold!)

      perform_enqueued_jobs { described_class.perform_later }
      user = User.last
      expect(user).not_to be_nil
      expect(user.created_at).to be > 10.hours.ago
    end
  end
end
