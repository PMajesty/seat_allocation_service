require 'rails_helper'

RSpec.describe CleanupProcessingSeatsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:venue) { Venue.create!(name: "Test Venue", grid_rows: 5, grid_cols: 5) }
  let(:event) { Event.create!(title: "Test Event", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.hour.from_now) }
  let(:user) { User.create!(email: "buyer@example.com", password: "password") }

  def create_seat(row, col, status, updated_at = Time.current)
    seat = Seat.create!(venue: venue, grid_row: row, grid_col: col)

    order = nil
    if status == :sold
      order = Order.create!(
        user: user,
        showtime: showtime,
        total_amount_cents: 1000,
        currency: "USD",
        status: :paid
      )
    end

    ShowtimeSeat.create!(
      showtime: showtime,
      seat: seat,
      status: status,
      updated_at: updated_at,
      order: order
    )
  end

  it "releases orphaned processing seats older than the timeout" do
    stuck_seat = create_seat(1, 1, :processing, 15.minutes.ago)
    active_seat = create_seat(1, 2, :processing, 1.minute.ago)
    sold_seat = create_seat(1, 3, :sold, 20.minutes.ago)
    available_seat = create_seat(1, 4, :available, 20.minutes.ago)

    described_class.perform_now

    stuck_seat.reload
    active_seat.reload
    sold_seat.reload
    available_seat.reload

    expect(stuck_seat.status).to eq("available")
    expect(active_seat.status).to eq("processing")
    expect(sold_seat.status).to eq("sold")
    expect(available_seat.status).to eq("available")
  end

  it "broadcasts updates for affected showtimes" do
    create_seat(1, 1, :processing, 15.minutes.ago)

    expect {
      described_class.perform_now
    }.to have_broadcasted_to("showtime_#{showtime.id}")
     .with(event: "refresh")
  end
end
