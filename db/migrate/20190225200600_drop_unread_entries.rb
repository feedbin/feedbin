class DropUnreadEntries < ActiveRecord::Migration[5.1]
  def change
    # drop_table(:unread_entries, force: true) if ActiveRecord::Base.connection.tables.include?("unread_entries")
  end
end
