class CreateShowtimeSeats < ActiveRecord::Migration[8.0]
  def change
    create_table :showtime_seats do |t|
      t.references :showtime, null: false, foreign_key: true
      t.references :seat, null: false, foreign_key: true

      t.integer :status, null: false, default: 0
      t.integer :price_cents
      t.datetime :reserved_until

      t.bigint :order_id

      t.timestamps
    end

    add_index :showtime_seats, [:showtime_id, :seat_id], unique: true
    add_index :showtime_seats, [:showtime_id, :status]
    add_index :showtime_seats, [:showtime_id, :reserved_until]
    add_index :showtime_seats, :order_id
  end
end
