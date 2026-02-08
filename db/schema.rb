# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_02_02_112907) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "events", force: :cascade do |t|
    t.string "title"
    t.integer "base_price_cents"
    t.string "currency", default: "USD"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "showtime_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_amount_cents"
    t.string "currency", default: "USD"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["showtime_id", "status"], name: "index_orders_on_showtime_id_and_status"
    t.index ["showtime_id"], name: "index_orders_on_showtime_id"
    t.index ["user_id", "created_at"], name: "index_orders_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.integer "status", default: 0
    t.string "idempotency_key"
    t.string "external_payment_id"
    t.integer "amount_cents"
    t.string "currency", default: "USD"
    t.jsonb "raw_webhook"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_payment_id"], name: "index_payments_on_external_payment_id", unique: true, where: "(external_payment_id IS NOT NULL)"
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", unique: true
    t.index ["order_id"], name: "index_payments_on_order_id"
  end

  create_table "seats", force: :cascade do |t|
    t.bigint "venue_id", null: false
    t.integer "grid_row"
    t.integer "grid_col"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["venue_id", "grid_row", "grid_col"], name: "index_seats_on_venue_id_and_grid_row_and_grid_col", unique: true
    t.index ["venue_id"], name: "index_seats_on_venue_id"
  end

  create_table "showtime_seats", force: :cascade do |t|
    t.bigint "showtime_id", null: false
    t.bigint "seat_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "price_cents"
    t.bigint "order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_showtime_seats_on_order_id"
    t.index ["seat_id"], name: "index_showtime_seats_on_seat_id"
    t.index ["showtime_id", "seat_id"], name: "index_showtime_seats_on_showtime_id_and_seat_id", unique: true
    t.index ["showtime_id", "status"], name: "index_showtime_seats_on_showtime_id_and_status"
    t.index ["showtime_id"], name: "index_showtime_seats_on_showtime_id"
    t.check_constraint "status = 1 AND order_id IS NOT NULL OR status <> 1 AND order_id IS NULL", name: "check_showtime_seats_status_order_consistency"
  end

  create_table "showtimes", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "venue_id", null: false
    t.datetime "starts_at"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_showtimes_on_event_id"
    t.index ["status", "starts_at"], name: "index_showtimes_on_status_and_starts_at"
    t.index ["venue_id", "starts_at"], name: "index_showtimes_on_venue_id_and_starts_at"
    t.index ["venue_id"], name: "index_showtimes_on_venue_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "showtime_seat_id", null: false
    t.string "code", null: false
    t.integer "status", default: 0
    t.datetime "redeemed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_tickets_on_code", unique: true
    t.index ["order_id"], name: "index_tickets_on_order_id"
    t.index ["showtime_seat_id"], name: "index_tickets_on_showtime_seat_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0
    t.integer "token_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "venues", force: :cascade do |t|
    t.string "name"
    t.integer "grid_rows"
    t.integer "grid_cols"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "orders", "showtimes"
  add_foreign_key "orders", "users"
  add_foreign_key "payments", "orders"
  add_foreign_key "seats", "venues"
  add_foreign_key "showtime_seats", "orders"
  add_foreign_key "showtime_seats", "seats"
  add_foreign_key "showtime_seats", "showtimes"
  add_foreign_key "showtimes", "events"
  add_foreign_key "showtimes", "venues"
  add_foreign_key "tickets", "orders"
  add_foreign_key "tickets", "showtime_seats"
end
