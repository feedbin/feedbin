class AddAliveToFeed < ActiveRecord::Migration
  def change
    add_column :feeds, :alive, :boolean, default: true
  end
end
