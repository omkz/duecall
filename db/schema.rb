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

ActiveRecord::Schema[8.1].define(version: 2026_09_10_001000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "call_attempts", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "contact_id", null: false
    t.datetime "created_at", null: false
    t.bigint "invoice_id", null: false
    t.integer "outcome"
    t.date "promise_to_pay_on"
    t.string "provider_call_id"
    t.jsonb "raw_result", default: {}, null: false
    t.text "reason"
    t.string "sentiment"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.text "summary"
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_call_attempts_on_contact_id"
    t.index ["invoice_id"], name: "index_call_attempts_on_invoice_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "email"
    t.string "name", null: false
    t.string "phone_number", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_contacts_on_customer_id"
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "external_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_customers_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.bigint "customer_id", null: false
    t.date "due_on", null: false
    t.string "external_id"
    t.date "issued_on"
    t.string "number", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "number"], name: "index_invoices_on_customer_id_and_number", unique: true
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "event_id"], name: "index_webhook_events_on_provider_and_event_id", unique: true
  end

  add_foreign_key "call_attempts", "contacts"
  add_foreign_key "call_attempts", "invoices"
  add_foreign_key "contacts", "customers"
  add_foreign_key "customers", "users"
  add_foreign_key "invoices", "customers"
  add_foreign_key "sessions", "users"
end
