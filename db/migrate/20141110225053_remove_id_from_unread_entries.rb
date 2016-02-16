class RemoveIdFromUnreadEntries < ActiveRecord::Migration
  def change
    remove_column :unread_entries, :id
  end
end
