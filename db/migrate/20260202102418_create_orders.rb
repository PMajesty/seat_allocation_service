class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :showtime, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :total_amount_cents
      t.string :currency, default: 'USD'

      t.timestamps
    end
    add_index :orders, [:user_id, :created_at]
    add_index :orders, [:showtime_id, :status]
  end
end
