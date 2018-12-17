class CreateEntries < ActiveRecord::Migration[4.2]
  def change
    create_table :entries do |t|
      t.integer :feed_id
      t.string :entry_id
      t.string :title
      t.string :url
      t.string :author
      t.text :summary
      t.text :content
      t.datetime :published
      t.datetime :updated

      t.timestamps
    end

    add_index :entries, :entry_id
    add_index :entries, :feed_id
    add_index :entries, [:feed_id, :entry_id], unique: true
  end
end
