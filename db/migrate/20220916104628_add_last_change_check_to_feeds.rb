class AddLastChangeCheckToFeeds < ActiveRecord::Migration[7.0]
  def change
    add_column :feeds, :last_change_check, :datetime
  end
end
