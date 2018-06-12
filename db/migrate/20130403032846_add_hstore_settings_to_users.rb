class AddHstoreSettingsToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :settings, :hstore
  end
end
