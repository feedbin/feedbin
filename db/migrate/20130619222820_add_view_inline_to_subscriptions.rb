class AddViewInlineToSubscriptions < ActiveRecord::Migration
  def change
    add_column :subscriptions, :view_inline, :boolean, default: false
  end
end
