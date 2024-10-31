class AddImageProviderColumns < ActiveRecord::Migration[7.2]
  def change
    add_column :entries, :image_provider, :bigint
    add_column :entries, :image_provider_id, :text

    add_column :feeds, :image_provider, :bigint
    add_column :feeds, :image_provider_id, :text
  end
end
