class AddResponseToInAppPurchases < ActiveRecord::Migration[4.2]
  def change
    add_column :in_app_purchases, :response, :json
  end
end
