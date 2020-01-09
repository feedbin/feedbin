class AddViewModeToSubscriptions < ActiveRecord::Migration[6.0]
  def up
    add_column :subscriptions, :view_mode, :bigint
    change_column_default(:subscriptions, :view_mode, 0)
  end

  def down
    remove_column :subscriptions, :view_mode
  end
end
