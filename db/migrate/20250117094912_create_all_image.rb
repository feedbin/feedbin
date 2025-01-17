class CreateAllImage < ActiveRecord::Migration[7.2]
  def change
    create_table :images do |t|
      t.bigint :provider,            null: false
      t.bigint :source,              null: false, default: 0
      t.text   :provider_id,         null: false
      t.text   :url,                 null: false
      t.text   :storage_url,         null: false
      t.bigint :width,               null: false
      t.bigint :height,              null: false
      t.bigint :bytesize,            null: false
      t.text   :placeholder_color,   null: false
      t.uuid   :url_fingerprint,     null: false
      t.uuid   :image_fingerprint,   null: false
      t.uuid   :storage_fingerprint, null: false
      t.timestamps
      t.jsonb  :data,                null: false, default: {}
      t.jsonb  :settings,            null: false, default: {}

    end

    create_table :image_tags do |t|
      t.references :image, null: false, foreign_key: true
      t.references :imageable, polymorphic: true, null: false

      t.timestamps
    end

    add_index :images,     [:url_fingerprint, :provider],               unique: true
    add_index :image_tags, [:imageable_id, :image_id, :imageable_type], unique: true

    add_column :entries, :image_provider,    :bigint
    add_column :entries, :image_provider_id, :text
    add_column :feeds,   :image_provider,    :bigint
    add_column :feeds,   :image_provider_id, :text
  end
end
