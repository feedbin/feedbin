class CreateEntryRenderings < ActiveRecord::Migration[8.1]
  def up
    create_table :entry_renderings, id: false do |t|
      t.bigint :entry_id, null: false
      t.integer :version, null: false, limit: 2
      t.binary :blob, null: false
    end
    # A new, empty table: neither statement locks anything in use.
    safety_assured do
      execute "ALTER TABLE entry_renderings ADD PRIMARY KEY (entry_id)"
      execute "ALTER TABLE entry_renderings ALTER COLUMN blob SET STORAGE EXTERNAL"
    end
  end

  def down
    drop_table :entry_renderings
  end
end
