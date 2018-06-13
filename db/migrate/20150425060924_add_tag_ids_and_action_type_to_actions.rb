class AddTagIdsAndActionTypeToActions < ActiveRecord::Migration[4.2]
  def change
    add_column :actions, :tag_ids, :integer, array: true, default: []
    add_column :actions, :action_type, :integer, default: 0
    add_column :actions, :computed_feed_ids, :integer, array: true, default: []
  end
end
