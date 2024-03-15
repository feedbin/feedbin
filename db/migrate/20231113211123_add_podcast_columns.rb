class AddPodcastColumns < ActiveRecord::Migration[7.1]
  def change
    add_column :queued_entries, :skipped_chapters, :jsonb, null: false, default: []
    add_column :podcast_subscriptions, :download_filter, :string
    add_column :podcast_subscriptions, :download_filter_type, :bigint, null: false, default: 0
    add_column :podcast_subscriptions, :chapter_filter, :string
    add_column :podcast_subscriptions, :chapter_filter_type, :bigint, null: false, default: 1
  end
end
