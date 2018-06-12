class AddSuspendedToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :suspended, :boolean, default: false
  end
end
