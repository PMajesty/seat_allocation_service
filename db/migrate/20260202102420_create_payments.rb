class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.integer :status, default: 0
      t.string :idempotency_key
      t.string :external_payment_id
      t.integer :amount_cents
      t.string :currency, default: 'USD'
      t.jsonb :raw_webhook

      t.timestamps
    end
    add_index :payments, :idempotency_key, unique: true
    add_index :payments, :external_payment_id, unique: true, where: "external_payment_id IS NOT NULL"
  end
end
