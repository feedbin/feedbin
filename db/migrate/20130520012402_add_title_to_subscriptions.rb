class AddTitleToSubscriptions < ActiveRecord::Migration[4.2]
  def change
    add_column :subscriptions, :title, :text
  end
end
