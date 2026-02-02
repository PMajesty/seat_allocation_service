class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string :title
      t.integer :base_price_cents
      t.string :currency, default: 'USD'
      t.boolean :active, default: true

      t.timestamps
    end
  end
end
