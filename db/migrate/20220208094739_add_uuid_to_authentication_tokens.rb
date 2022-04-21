class AddUuidToAuthenticationTokens < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!
  def up
    execute <<~SQL
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    SQL
    add_column :authentication_tokens, :uuid, :uuid, default: -> { "uuid_generate_v4()" }, null: false
    add_index :authentication_tokens, :uuid, algorithm: :concurrently
  end
  def down
    remove_index :authentication_tokens, :uuid
    remove_column :authentication_tokens, :uuid
  end
end
