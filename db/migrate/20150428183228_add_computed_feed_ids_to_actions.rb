class AddComputedFeedIdsToActions < ActiveRecord::Migration
  def change
    add_column :actions, :computed_feed_ids, :integer, array: true, default: []
  end
end
