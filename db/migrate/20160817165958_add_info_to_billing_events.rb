class AddInfoToBillingEvents < ActiveRecord::Migration
  def change
    add_column :billing_events, :info, :json
  end
end
