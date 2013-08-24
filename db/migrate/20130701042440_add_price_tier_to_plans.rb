class AddPriceTierToPlans < ActiveRecord::Migration
  def change
    add_column :plans, :price_tier, :integer
  end
end

