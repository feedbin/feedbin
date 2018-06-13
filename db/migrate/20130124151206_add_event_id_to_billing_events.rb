class AddEventIdToBillingEvents < ActiveRecord::Migration[4.2]
  def change
    add_column :billing_events, :event_id, :string
    add_index :billing_events, :event_id, unique: true
  end
end
