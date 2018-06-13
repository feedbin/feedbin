class UseTextForFeedAndEntryProperties < ActiveRecord::Migration[4.2]
  def up
    change_table :entries do |t|
      t.change :title, :text
      t.change :url, :text
      t.change :author, :text
    end
    change_table :feeds do |t|
      t.change :feed_title, :text
      t.change :feed_url, :text
      t.change :site_url, :text
    end
  end

  def down
    change_table :entries do |t|
      t.change :title, :string
      t.change :url, :string
      t.change :author, :string
    end
    change_table :feeds do |t|
      t.change :feed_title, :string
      t.change :feed_url, :string
      t.change :site_url, :string
    end
  end
end
