# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20130820123435) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "hstore"

  create_table "billing_events", force: true do |t|
    t.text     "details"
    t.string   "event_type"
    t.integer  "billable_id"
    t.string   "billable_type"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.string   "event_id"
  end

  add_index "billing_events", ["billable_id", "billable_type"], name: "index_billing_events_on_billable_id_and_billable_type", using: :btree
  add_index "billing_events", ["event_id"], name: "index_billing_events_on_event_id", unique: true, using: :btree

  create_table "coupons", force: true do |t|
    t.integer  "user_id"
    t.string   "coupon_code"
    t.string   "sent_to"
    t.boolean  "redeemed",    default: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "coupons", ["user_id"], name: "index_coupons_on_user_id", using: :btree

  create_table "entries", force: true do |t|
    t.integer  "feed_id"
    t.text     "title"
    t.text     "url"
    t.text     "author"
    t.text     "summary"
    t.text     "content"
    t.datetime "published"
    t.datetime "updated"
    t.datetime "created_at",                        null: false
    t.datetime "updated_at",                        null: false
    t.text     "entry_id"
    t.string   "public_id"
    t.string   "old_public_id"
    t.integer  "starred_entries_count", default: 0, null: false
  end

  add_index "entries", ["feed_id"], name: "index_entries_on_feed_id", using: :btree
  add_index "entries", ["public_id"], name: "index_entries_on_public_id", unique: true, using: :btree

  create_table "feeds", force: true do |t|
    t.text     "title"
    t.text     "feed_url"
    t.text     "site_url"
    t.text     "etag"
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.datetime "last_modified"
    t.integer  "subscriptions_count", default: 0, null: false
  end

  add_index "feeds", ["feed_url"], name: "index_feeds_on_feed_url", unique: true, using: :btree

  create_table "import_items", force: true do |t|
    t.integer  "import_id"
    t.text     "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string   "item_type"
  end

  add_index "import_items", ["import_id"], name: "index_import_items_on_import_id", using: :btree

  create_table "imports", force: true do |t|
    t.integer  "user_id"
    t.boolean  "complete",   default: false
    t.datetime "created_at",                 null: false
    t.datetime "updated_at",                 null: false
    t.string   "upload"
  end

  create_table "plans", force: true do |t|
    t.string   "stripe_id"
    t.string   "name"
    t.decimal  "price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "price_tier"
  end

  create_table "sharing_services", force: true do |t|
    t.integer  "user_id"
    t.text     "label"
    t.text     "url"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sharing_services", ["user_id"], name: "index_sharing_services_on_user_id", using: :btree

  create_table "starred_entries", force: true do |t|
    t.integer  "user_id"
    t.integer  "feed_id"
    t.integer  "entry_id"
    t.datetime "published"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "starred_entries", ["entry_id"], name: "index_starred_entries_on_entry_id", using: :btree
  add_index "starred_entries", ["feed_id"], name: "index_starred_entries_on_feed_id", using: :btree
  add_index "starred_entries", ["published"], name: "index_starred_entries_on_published", using: :btree
  add_index "starred_entries", ["user_id", "entry_id"], name: "index_starred_entries_on_user_id_and_entry_id", unique: true, using: :btree
  add_index "starred_entries", ["user_id"], name: "index_starred_entries_on_user_id", using: :btree

  create_table "subscriptions", force: true do |t|
    t.integer  "user_id"
    t.integer  "feed_id"
    t.datetime "created_at",                  null: false
    t.datetime "updated_at",                  null: false
    t.text     "title"
    t.boolean  "view_inline", default: false
  end

  add_index "subscriptions", ["created_at"], name: "index_subscriptions_on_created_at", using: :btree
  add_index "subscriptions", ["feed_id"], name: "index_subscriptions_on_feed_id", using: :btree
  add_index "subscriptions", ["user_id", "feed_id"], name: "index_subscriptions_on_user_id_and_feed_id", unique: true, using: :btree
  add_index "subscriptions", ["user_id"], name: "index_subscriptions_on_user_id", using: :btree

  create_table "taggings", force: true do |t|
    t.integer  "feed_id"
    t.integer  "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "tag_id"
  end

  add_index "taggings", ["tag_id"], name: "index_taggings_on_tag_id", using: :btree
  add_index "taggings", ["user_id", "feed_id"], name: "index_taggings_on_user_id_and_feed_id", using: :btree
  add_index "taggings", ["user_id", "tag_id"], name: "index_taggings_on_user_id_and_tag_id", using: :btree
  add_index "taggings", ["user_id"], name: "index_taggings_on_user_id", using: :btree

  create_table "tags", force: true do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "tags", ["name"], name: "index_tags_on_name", using: :btree

  create_table "unread_entries", force: true do |t|
    t.integer  "user_id"
    t.integer  "feed_id"
    t.integer  "entry_id"
    t.datetime "published"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "entry_created_at"
  end

  add_index "unread_entries", ["entry_id"], name: "index_unread_entries_on_entry_id", using: :btree
  add_index "unread_entries", ["feed_id"], name: "index_unread_entries_on_feed_id", using: :btree
  add_index "unread_entries", ["user_id", "entry_id"], name: "index_unread_entries_on_user_id_and_entry_id", unique: true, using: :btree
  add_index "unread_entries", ["user_id", "feed_id", "published"], name: "index_unread_entries_on_user_id_and_feed_id_and_published", using: :btree
  add_index "unread_entries", ["user_id", "published"], name: "index_unread_entries_on_user_id_and_published", using: :btree
  add_index "unread_entries", ["user_id"], name: "index_unread_entries_on_user_id", using: :btree

  create_table "users", force: true do |t|
    t.string   "email"
    t.string   "password_digest"
    t.string   "customer_id"
    t.string   "last_4_digits"
    t.integer  "plan_id"
    t.boolean  "admin",                  default: false
    t.boolean  "suspended",              default: false
    t.datetime "created_at",                             null: false
    t.datetime "updated_at",                             null: false
    t.string   "auth_token"
    t.string   "password_reset_token"
    t.datetime "password_reset_sent_at"
    t.hstore   "settings"
    t.string   "starred_token"
    t.string   "inbound_email_token"
  end

  add_index "users", ["auth_token"], name: "index_users_on_auth_token", unique: true, using: :btree
  add_index "users", ["customer_id"], name: "index_users_on_customer_id", unique: true, using: :btree
  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["inbound_email_token"], name: "index_users_on_inbound_email_token", unique: true, using: :btree
  add_index "users", ["password_reset_token"], name: "index_users_on_password_reset_token", unique: true, using: :btree
  add_index "users", ["starred_token"], name: "index_users_on_starred_token", unique: true, using: :btree

end
