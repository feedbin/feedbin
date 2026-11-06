class CreateEntryVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :entry_videos, id: false do |t|
      t.references :entry, null: false, index: true, foreign_key: {on_delete: :cascade}
      t.text :provider_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :entry_videos, [:provider_id, :entry_id], unique: true
  end
end
