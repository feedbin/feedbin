class AddSelectedEntryToUsers < ActiveRecord::Migration
  def change
    add_column :users, :selected_entry, :integer
  end
end
