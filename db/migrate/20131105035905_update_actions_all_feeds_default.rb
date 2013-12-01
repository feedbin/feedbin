class UpdateActionsAllFeedsDefault < ActiveRecord::Migration
  def change
    change_column :actions, :all_feeds, :boolean, default: false
  end
end
