puts "== Seeding Database =="

puts "Preparing Elasticsearch..."
begin
  Event.__elasticsearch__.create_index!(force: true)
rescue => e
  puts "Elasticsearch warning: #{e.message}"
end

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

  puts "Creating Core Events..."
  event1 = Event.create!(title: "Symphony No. 9", base_price_cents: 12000, currency: "USD", active: true)
  event2 = Event.create!(title: "Rock Legends Live", base_price_cents: 8500, currency: "USD", active: true)
  event3 = Event.create!(title: "Jazz Nights", base_price_cents: 6000, currency: "USD", active: true)
  event4 = Event.create!(title: "Comedy Special", base_price_cents: 5500, currency: "USD", active: true)
  event5 = Event.create!(title: "The Nutcracker", base_price_cents: 11000, currency: "USD", active: true)
  event6 = Event.create!(title: "Indie Showcase", base_price_cents: 4500, currency: "USD", active: true)
  event7 = Event.create!(title: "Magic & Mystery", base_price_cents: 7000, currency: "USD", active: true)

  puts "Creating Bulk Events..."
  bulk_events = []
  adjectives = ["Electric", "Acoustic", "Midnight", "Golden", "Neon", "Silent", "Epic", "Urban", "Classic", "Modern"]
  nouns = ["Orchestra", "Jam", "Gala", "Fest", "Recital", "Opera", "Ballet", "Rave", "Ensemble", "Quartet"]

  200.times do |i|
    title = "#{adjectives.sample} #{nouns.sample} #{i + 1}"
    price = rand(3000..15000)
    bulk_events << {
      title: title,
      base_price_cents: price,
      currency: "USD",
      active: true,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  Event.insert_all!(bulk_events)

  all_events = Event.all.to_a
  price_map = all_events.index_by(&:id).transform_values(&:base_price_cents)

  showtimes_data = []

  core_events = [event1, event2, event3, event4, event5, event6, event7]
  core_events.each_with_index do |evt, idx|
    showtimes_data << {
      event_id: evt.id,
      venue_id: venue.id,
      starts_at: (idx + 1).days.from_now.change(hour: 19, min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  all_events.sample(50).each do |evt|
    next if core_events.include?(evt)
    showtimes_data << {
      event_id: evt.id,
      venue_id: venue.id,
      starts_at: rand(1..30).days.from_now.change(hour: rand(18..22), min: 0),
      status: 0,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  Showtime.insert_all!(showtimes_data)

  showtimes = Showtime.all.to_a
  showtime_seats_data = []

  puts "Generating Seats (this may take a moment)..."
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

puts "Indexing Events in Elasticsearch..."
Event.import(force: true)
