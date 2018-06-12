class IndexUsersOnLowercaseEmail < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    execute "CREATE UNIQUE INDEX CONCURRENTLY index_users_on_lower_email ON users (LOWER(email))"
    remove_index :users, :email
  end

  def down
    execute "DROP INDEX index_users_on_lower_email"
    add_index :users, :email, algorithm: :concurrently, unique: true
  end
end
