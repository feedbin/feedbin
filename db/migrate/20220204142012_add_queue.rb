class AddQueue < ActiveRecord::Migration[7.0]
  def change
    create_table :queued_entries do |t|
      t.references :user, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :entry, null: false, foreign_key: { on_delete: :cascade }
      t.references :feed, null: false
      t.bigint :order, null: false, default: -> { "extract(epoch from now())" }
      t.bigint :progress, null: false, default: 0
      t.bigint :duration, null: false, default: 0

      t.timestamps
    end

    add_index :queued_entries, [:user_id, :entry_id], unique: true
    add_index :queued_entries, [:user_id, :order]
  end
end
