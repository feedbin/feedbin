class AddPushExpirationToFeeds < ActiveRecord::Migration
  def change
    add_column :feeds, :push_expiration, :datetime
  end
end
