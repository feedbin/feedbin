class UpdateActionsAllFeedsDefault < ActiveRecord::Migration[4.2]
  def change
    change_column :actions, :all_feeds, :boolean, default: false
  end
end
