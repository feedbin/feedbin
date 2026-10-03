class DropUnusedTablesAndColumns < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      drop_table :favicons do |t|
        t.text :host
        t.text :favicon
        t.datetime :created_at, precision: nil
        t.datetime :updated_at, precision: nil
        t.json :data
        t.string :url
        t.index :host, unique: true
      end

      drop_table :remote_files do |t|
        t.uuid :fingerprint, null: false
        t.text :original_url, null: false
        t.text :storage_url, null: false
        t.jsonb :data, default: {}
        t.jsonb :settings, default: {}
        t.timestamps
        t.index :fingerprint, unique: true
      end

      remove_column :users, :last_4_digits, :string, limit: 255
      remove_column :users, :twitter_auth_failures, :bigint
      remove_column :subscriptions, :show_status, :bigint, default: 0, null: false
      remove_column :import_items, :item_type, :string, limit: 255
    end
  end
end
