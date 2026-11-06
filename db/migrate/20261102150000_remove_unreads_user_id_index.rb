# Every query on unreads by user_id can use one of the composite indexes that
# lead with user_id, so this one is only a cost on the busiest insert path.
class RemoveUnreadsUserIdIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    remove_index :unreads, :user_id, name: "index_unreads_on_user_id", algorithm: :concurrently, if_exists: true
  end
end
