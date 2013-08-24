class AddTitleToSubscriptions < ActiveRecord::Migration
  def change
    add_column :subscriptions, :title, :text
  end
end
