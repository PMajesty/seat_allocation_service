puts "== Seeding Database =="

ActiveRecord::Base.transaction do
  Ticket.delete_all
  Payment.delete_all
  Order.delete_all
  ShowtimeSeat.delete_all
  Showtime.delete_all
  Seat.delete_all
  Venue.delete_all
  Event.delete_all
  User.delete_all

  common_password = BCrypt::Password.create("12345678")
  users = []

  users << {
    email: "admin@showtime.com",
    password_digest: common_password,
    role: 1,
    created_at: 1.year.ago,
    updated_at: 1.year.ago
  }

  users << {
    email: "visitor@showtime.com",
    password_digest: common_password,
    role: 0,
    created_at: Time.current,
    updated_at: Time.current
  }

  100.times do |i|
    users << {
      email: "trusted_#{i}@example.com",
      password_digest: common_password,
      role: 0,
      created_at: 1.year.ago,
      updated_at: 1.year.ago
    }
  end
  User.insert_all!(users)

  venue = Venue.create!(name: "The Grand Hall", grid_rows: 9, grid_cols: 10)

  seats_data = []
  (1..9).each do |row|
    (1..10).each do |col|
      seats_data << {
        venue_id: venue.id,
        grid_row: row,
        grid_col: col,
        active: true,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end
  Seat.insert_all!(seats_data)

  seats = Seat.where(venue_id: venue.id).to_a

  event1 = Event.create!(title: "Symphony No. 9", base_price_cents: 12000, currency: "USD", active: true)
  event2 = Event.create!(title: "Rock Legends Live", base_price_cents: 8500, currency: "USD", active: true)
  event3 = Event.create!(title: "Jazz Nights", base_price_cents: 6000, currency: "USD", active: true)
  event4 = Event.create!(title: "Comedy Special", base_price_cents: 5500, currency: "USD", active: true)
  event5 = Event.create!(title: "The Nutcracker", base_price_cents: 11000, currency: "USD", active: true)
  event6 = Event.create!(title: "Indie Showcase", base_price_cents: 4500, currency: "USD", active: true)
  event7 = Event.create!(title: "Magic & Mystery", base_price_cents: 7000, currency: "USD", active: true)

  all_events = [event1, event2, event3, event4, event5, event6, event7]
  price_map = all_events.index_by(&:id).transform_values(&:base_price_cents)

  showtimes_data = [
    {
      event_id: event1.id,
      venue_id: venue.id,
      starts_at: 1.day.from_now.change(hour: 19, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event1.id,
      venue_id: venue.id,
      starts_at: 2.days.from_now.change(hour: 19, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event2.id,
      venue_id: venue.id,
      starts_at: 3.days.from_now.change(hour: 20, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event3.id,
      venue_id: venue.id,
      starts_at: 4.days.from_now.change(hour: 18, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event4.id,
      venue_id: venue.id,
      starts_at: 5.days.from_now.change(hour: 20, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event5.id,
      venue_id: venue.id,
      starts_at: 6.days.from_now.change(hour: 19, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event6.id,
      venue_id: venue.id,
      starts_at: 7.days.from_now.change(hour: 21, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    },
    {
      event_id: event7.id,
      venue_id: venue.id,
      starts_at: 8.days.from_now.change(hour: 19, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    }
  ]
  Showtime.insert_all!(showtimes_data)

  showtimes = Showtime.all.to_a

  showtime_seats_data = []

  showtimes.each do |showtime|
    price = price_map[showtime.event_id]

    seats.each do |seat|
      showtime_seats_data << {
        showtime_id: showtime.id,
        seat_id: seat.id,
        status: 0,
        price_cents: price,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end

  showtime_seats_data.each_slice(1000) do |batch|
    ShowtimeSeat.insert_all!(batch)
  end

  puts "== Seed Complete =="
end
