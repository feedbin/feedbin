class AddImageProviderColumns < ActiveRecord::Migration[7.2]

  def change
    add_column :entries, :image_provider, :bigint
    add_column :entries, :image_provider_id, :text

    add_column :feeds, :image_provider, :bigint
    add_column :feeds, :image_provider_id, :text

    add_column :images, :composite_id, :uuid, null: false
    safety_assured { add_index :images, :composite_id, unique: true }
    remove_index :images, [:provider, :provider_id]
  end
end
