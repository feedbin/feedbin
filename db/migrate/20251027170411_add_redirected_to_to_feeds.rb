class AddRedirectedToToFeeds < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!
  def change
    add_column :feeds, :redirected_to, :text
    add_index :feeds, :redirected_to, where: "redirected_to IS NOT NULL", algorithm: :concurrently
  end
end
