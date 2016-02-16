class AddResponseToInAppPurchases < ActiveRecord::Migration
  def change
    add_column :in_app_purchases, :response, :json
  end
end
