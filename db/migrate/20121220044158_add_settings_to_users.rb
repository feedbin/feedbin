class AddSettingsToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :settings, :text
  end
end
