class RecreateImages < ActiveRecord::Migration[8.1]
  def change
    create_table :images do |t|
      t.bigint :provider,             null: false
      t.text   :provider_id,          null: false
      t.bigint :feed_id
      t.text   :url,                  null: false
      t.uuid   :url_fingerprint,      null: false
      t.uuid   :image_fingerprint,    null: false
      t.uuid   :original_fingerprint, null: false
      t.text   :storage_path,         null: false
      t.bigint :width,                null: false
      t.bigint :height,               null: false
      t.bigint :bytesize,             null: false
      t.text   :placeholder_color,    null: false
      t.jsonb  :data,                 null: false, default: {}
      t.text   :variant,              null: false

      t.timestamps

    end
    add_index :images, [:provider, :provider_id], unique: true
    add_index :images, :url_fingerprint
    add_index :images, [:feed_id, :image_fingerprint]
    add_index :images, :storage_path
  end
end
