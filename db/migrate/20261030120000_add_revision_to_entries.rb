class AddRevisionToEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :entries, :revision, :integer, null: false, default: 1
    add_column :entries, :edited_at, :datetime
    # Only edited entries have one, and API v3's edited_after= reads them in
    # edited_at order.
    add_index :entries, [:edited_at, :id], where: "edited_at IS NOT NULL", algorithm: :concurrently
  end
end
