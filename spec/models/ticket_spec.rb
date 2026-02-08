require 'rails_helper'

RSpec.describe Ticket, type: :model do
  let(:user) { User.create!(email: "ticket@example.com", password: "password") }
  let(:venue) { Venue.create!(name: "TVenue", grid_rows: 1, grid_cols: 1) }
  let(:event) { Event.create!(title: "TEvent", base_price_cents: 1000) }
  let(:showtime) { Showtime.create!(event: event, venue: venue, starts_at: 1.day.from_now) }
  let(:seat) { Seat.create!(venue: venue, grid_row: 1, grid_col: 1) }
  let(:showtime_seat) { ShowtimeSeat.create!(showtime: showtime, seat: seat, price_cents: 1000) }
  let(:order) { Order.create!(user: user, showtime: showtime, total_amount_cents: 1000, status: :paid) }

  describe "callbacks" do
    it "generates a unique code on creation" do
      ticket = Ticket.create!(order: order, showtime_seat: showtime_seat)
      expect(ticket.code).to be_present
      expect(ticket.code.length).to eq(8)
    end

    it "retries if code collision occurs" do
      existing_ticket = Ticket.create!(order: order, showtime_seat: showtime_seat, code: "ABC12345")

      seat2 = Seat.create!(venue: venue, grid_row: 1, grid_col: 2)
      showtime_seat2 = ShowtimeSeat.create!(showtime: showtime, seat: seat2, price_cents: 1000)

      allow(SecureRandom).to receive(:hex).and_return("ABC12345", "NEWCODE1")

      new_ticket = Ticket.create!(order: order, showtime_seat: showtime_seat2)
      expect(new_ticket.code).to eq("NEWCODE1")
    end
  end
end
