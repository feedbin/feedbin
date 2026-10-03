class RemoveUnusedColumnsFromEntries < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :entries, :old_public_id, :string, limit: 255
      remove_column :entries, :processed_image_url, :text
      remove_column :entries, :image_url, :text
      remove_column :entries, :thread_id, :bigint
      remove_column :entries, :image, :json
      remove_column :entries, :source, :text
      remove_column :entries, :main_tweet_id, :text
    end
  end
end
