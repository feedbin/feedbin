class AddActiveToAuthenticationTokens < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  def change
    add_column :authentication_tokens, :active, :boolean, default: true, null: false
    add_index :authentication_tokens, [:purpose, :token, :active], algorithm: :concurrently
  end
end
