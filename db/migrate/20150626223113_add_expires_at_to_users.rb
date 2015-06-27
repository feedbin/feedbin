class AddExpiresAtToUsers < ActiveRecord::Migration
  def change
    add_column :users, :expires_at, :datetime
    add_index :users, :expires_at
  end
end
