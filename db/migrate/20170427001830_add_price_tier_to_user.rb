class AddPriceTierToUser < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :price_tier, :integer
  end
end
