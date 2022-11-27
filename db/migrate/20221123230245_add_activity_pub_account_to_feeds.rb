class AddActivityPubAccountToFeeds < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :feeds, :activity_pub_account, :text
    add_index :feeds, :activity_pub_account, where: "activity_pub_account IS NOT NULL", algorithm: :concurrently, unique: true
  end
end
