class AddPushExpirationToFeeds < ActiveRecord::Migration[4.2]
  def change
    add_column :feeds, :push_expiration, :datetime
  end
end
