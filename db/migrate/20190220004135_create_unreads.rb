class CreateUnreads < ActiveRecord::Migration[5.1]
  def change
    create_table :unreads do |t|
      t.references :user, foreign_key: false, null: false, index: true
      t.references :feed, foreign_key: false, null: false, index: true
      t.references :entry, foreign_key: false, null: false, index: true
      t.datetime :published, null: false
      t.datetime :entry_created_at, null: false

      t.timestamps
    end

    add_foreign_key :unreads, :entries, on_delete: :cascade

    add_index :unreads, [:user_id, :entry_id], unique: true
    add_index :unreads, [:user_id, :created_at]
    add_index :unreads, [:user_id, :feed_id, :published]
    add_index :unreads, [:user_id, :published]
  end
end


