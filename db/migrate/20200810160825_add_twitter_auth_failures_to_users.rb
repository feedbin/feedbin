class AddTwitterAuthFailuresToUsers < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!
  def change
    add_column :users, :twitter_auth_failures, :bigint
    add_index :users, :twitter_auth_failures, algorithm: :concurrently
  end
end
