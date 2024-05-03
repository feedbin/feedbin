class CreateImages < ActiveRecord::Migration[7.1]
  def change
    create_table :images do |t|
      t.bigint :provider,          null: false
      t.text   :provider_id,       null: false
      t.text   :url,               null: false
      t.uuid   :url_fingerprint,   null: false
      t.text   :storage_url,       null: false
      t.uuid   :image_fingerprint, null: false
      t.bigint :width,             null: false
      t.bigint :height,            null: false
      t.text   :placeholder_color, null: false
      t.jsonb  :data,              null: false, default: {}
      t.jsonb  :settings,          null: false, default: {}

      t.timestamps
    end
    add_index :images, [:provider, :provider_id], unique: true
    add_index :images, :url_fingerprint
  end
end
