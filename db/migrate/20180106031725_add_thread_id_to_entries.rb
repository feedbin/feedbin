class AddThreadIdToEntries < ActiveRecord::Migration[5.1]
  disable_ddl_transaction!

  def change
    add_column :entries, :thread_id, :bigint
    add_index :entries, :thread_id, where: "thread_id IS NOT NULL", algorithm: :concurrently
  end
end
