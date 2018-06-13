class AddInfoToBillingEvents < ActiveRecord::Migration[4.2]
  def change
    add_column :billing_events, :info, :json
  end
end
