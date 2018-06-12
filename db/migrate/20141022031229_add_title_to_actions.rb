class AddTitleToActions < ActiveRecord::Migration[4.2]
  def change
    add_column :actions, :title, :text
  end
end
