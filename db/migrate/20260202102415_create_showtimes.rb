class CreateShowtimes < ActiveRecord::Migration[8.0]
  def change
    create_table :showtimes do |t|
      t.references :event, null: false, foreign_key: true
      t.references :venue, null: false, foreign_key: true
      t.datetime :starts_at
      t.integer :status, default: 0

      t.timestamps
    end
    add_index :showtimes, [:venue_id, :starts_at]
    add_index :showtimes, [:status, :starts_at]
  end
end
