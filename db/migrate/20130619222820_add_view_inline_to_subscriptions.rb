class AddViewInlineToSubscriptions < ActiveRecord::Migration[4.2]
  def change
    add_column :subscriptions, :view_inline, :boolean, default: false
  end
end
