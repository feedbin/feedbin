class AddSubscriptionsCountToFeeds < ActiveRecord::Migration[4.2]
  def self.up
    add_column :feeds, :subscriptions_count, :integer, null: false, default: 0
    Feed.reset_column_information
    Feed.all.each do |feed|
      Feed.reset_counters(feed.id, :subscriptions)
    end
  end

  def self.down
    remove_column :feeds, :subscriptions_count
  end
end
