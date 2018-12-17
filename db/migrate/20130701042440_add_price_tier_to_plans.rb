class AddPriceTierToPlans < ActiveRecord::Migration[4.2]
  def change
    add_column :plans, :price_tier, :integer
  end
end
