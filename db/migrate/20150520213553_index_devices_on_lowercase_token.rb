class IndexDevicesOnLowercaseToken < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    remove_index :devices, :token
    execute "CREATE UNIQUE INDEX CONCURRENTLY index_devices_on_lower_tokens ON devices (LOWER(token))"
  end

  def down
    execute "DROP INDEX index_devices_on_lower_tokens"
    add_index :devices, :token, algorithm: :concurrently
  end
end
