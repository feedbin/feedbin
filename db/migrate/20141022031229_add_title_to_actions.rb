class AddTitleToActions < ActiveRecord::Migration
  def change
    add_column :actions, :title, :text
  end
end
