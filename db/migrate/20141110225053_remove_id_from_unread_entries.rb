class RemoveIdFromUnreadEntries < ActiveRecord::Migration[4.2]
  def change
    remove_column :unread_entries, :id
  end
end
