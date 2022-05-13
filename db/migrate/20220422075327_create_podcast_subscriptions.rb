class CreatePodcastSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :podcast_subscriptions do |t|
      t.references :user,   null: false, foreign_key: { on_delete: :cascade }
      t.references :feed,   null: false, foreign_key: { on_delete: :cascade }
      t.bigint     :status, null: false, default: 0
      t.text       :title
      t.timestamps
    end
    add_index :podcast_subscriptions, [:user_id, :feed_id], unique: true
  end
end
