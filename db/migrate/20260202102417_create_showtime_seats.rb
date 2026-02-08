class CreateShowtimeSeats < ActiveRecord::Migration[8.0]
  def change
    create_table :showtime_seats do |t|
      t.references :showtime, null: false, foreign_key: true
      t.references :seat, null: false, foreign_key: true

      t.integer :status, null: false, default: 0
      t.integer :price_cents

      t.bigint :order_id

      t.timestamps

      t.check_constraint "((status = 1) AND (order_id IS NOT NULL)) OR ((status != 1) AND (order_id IS NULL))", name: "check_showtime_seats_status_order_consistency"
    end

    add_index :showtime_seats, [:showtime_id, :seat_id], unique: true
    add_index :showtime_seats, [:showtime_id, :status]
    add_index :showtime_seats, :order_id
  end
end
