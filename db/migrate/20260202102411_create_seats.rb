class CreateSeats < ActiveRecord::Migration[8.0]
  def change
    create_table :seats do |t|
      t.references :venue, null: false, foreign_key: true
      t.integer :grid_row
      t.integer :grid_col
      t.boolean :active, default: true

      t.timestamps
    end
    add_index :seats, [:venue_id, :grid_row, :grid_col], unique: true
  end
end
