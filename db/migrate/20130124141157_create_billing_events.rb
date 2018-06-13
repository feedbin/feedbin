class CreateBillingEvents < ActiveRecord::Migration[4.2]
  def change
    create_table :billing_events do |t|
      t.text :details
      t.string :event_type
      t.belongs_to :billable, polymorphic: true

      t.timestamps
    end
    add_index :billing_events, :event_type
    add_index :billing_events, [:billable_id, :billable_type]
  end
end
