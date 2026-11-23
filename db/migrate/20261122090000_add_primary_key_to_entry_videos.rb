# Deleting an entry cascades to entry_videos. Once a table is published for
# logical replication, Postgres refuses deletes from it unless it has a primary
# key, so the unique index becomes the primary key.
class AddPrimaryKeyToEntryVideos < ActiveRecord::Migration[8.1]
  INDEX = "index_entry_videos_on_provider_id_and_entry_id"

  # Both columns are already NOT NULL, so Postgres takes the index as it is,
  # without reading the table. The index is renamed to entry_videos_pkey.
  def up
    safety_assured do
      execute "ALTER TABLE entry_videos ADD CONSTRAINT entry_videos_pkey PRIMARY KEY USING INDEX #{INDEX}"
    end
  end

  # One transaction, so the table is never without its unique index.
  def down
    safety_assured do
      execute "ALTER TABLE entry_videos DROP CONSTRAINT entry_videos_pkey"
      execute "CREATE UNIQUE INDEX #{INDEX} ON entry_videos (provider_id, entry_id)"
    end
  end
end
