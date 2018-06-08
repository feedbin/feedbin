class AddSelectedEntryToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :selected_entry, :integer
  end
end
