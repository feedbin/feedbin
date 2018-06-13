class RemoveSettingsFromUsers < ActiveRecord::Migration[4.2]
  def up
    remove_column :users, :settings
  end

  def down
    add_column :users, :settings
  end
end
