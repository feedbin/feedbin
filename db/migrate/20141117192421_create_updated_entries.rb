class CreateUpdatedEntries < ActiveRecord::Migration[4.2]
  def change
    create_table :updated_entries, id: :bigserial do |t|
      t.belongs_to :user, index: true
      t.belongs_to :entry, index: true
      t.belongs_to :feed, index: true
      t.datetime :published
      t.datetime :updated

      t.timestamps
    end
    add_index :updated_entries, [:user_id, :entry_id], unique: true
  end
end
