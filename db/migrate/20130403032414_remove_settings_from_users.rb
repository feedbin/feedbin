class RemoveSettingsFromUsers < ActiveRecord::Migration
  def up
    remove_column :users, :settings
  end

  def down
    add_column :users, :settings
  end
end
