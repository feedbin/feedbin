class CreatePlaylists < ActiveRecord::Migration[7.0]
  def change
    create_table :playlists do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.text :title, null: false
      t.bigint :sort_order, null: false, default: 0

      t.timestamps
    end
    add_index :playlists, [:user_id, :title], unique: true

    add_column :queued_entries, :playlist_id, :bigint
    add_column :podcast_subscriptions, :playlist_id, :bigint
  end
end
