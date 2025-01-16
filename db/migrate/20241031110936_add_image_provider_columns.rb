class AddImageProviderColumns < ActiveRecord::Migration[7.2]

  def change
    add_column :entries, :image_provider, :bigint
    add_column :entries, :image_provider_id, :text

    add_column :feeds, :image_provider, :bigint
    add_column :feeds, :image_provider_id, :text

    # temporary for transition
    add_column :images, :original_storage_url, :text

    add_column :images, :final_url, :text, null: false
    add_column :images, :storage_fingerprint, :uuid, null: false
    safety_assured { add_index :images, :storage_fingerprint, unique: true }
  end
end
