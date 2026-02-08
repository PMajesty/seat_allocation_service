class AddForeignKeyFromShowtimeSeatsToOrders < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :showtime_seats, :orders
  end
end
