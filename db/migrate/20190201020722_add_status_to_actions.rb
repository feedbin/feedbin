class AddStatusToActions < ActiveRecord::Migration[5.1]
  def change
    add_column :actions, :status, :integer, default: 0
  end
end
