class CreateTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :tickets do |t|
      t.references :order, null: false, foreign_key: true
      t.references :showtime_seat, null: false, foreign_key: true, index: { unique: true }
      t.string :code, null: false
      t.integer :status, default: 0
      t.datetime :redeemed_at

      t.timestamps
    end
    add_index :tickets, :code, unique: true
  end
end
