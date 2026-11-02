# One version per (user, list), bumped by a statement-level trigger whenever
# rows join or leave the table behind a list. v3 list ETags read it, so an
# ETag changes on every membership change whatever code path made it.
class CreateSyncVersions < ActiveRecord::Migration[8.1]
  # Postgres allows transition tables only on single-event triggers, so each
  # table gets one trigger per event: inserts (and updates) read the new rows,
  # deletes read the old rows.
  TRIGGERS = {
    "unreads" => ["unread", %w[INSERT DELETE]],
    "starred_entries" => ["starred", %w[INSERT DELETE]],
    "subscriptions" => ["subscriptions", %w[INSERT UPDATE DELETE]],
    "taggings" => ["subscriptions", %w[INSERT DELETE]]
  }.freeze

  def up
    create_table :sync_versions, id: false do |t|
      t.bigint :user_id, null: false
      t.text :list, null: false
      t.bigint :version, null: false, default: 0
    end

    # The table is new and empty. CREATE TRIGGER takes a brief SHARE ROW
    # EXCLUSIVE lock on each table it is added to.
    safety_assured do
      execute "ALTER TABLE sync_versions ADD PRIMARY KEY (user_id, list)"
      {"inserted" => "new_rows", "deleted" => "old_rows"}.each do |suffix, rows|
        execute <<~SQL
          CREATE FUNCTION bump_sync_version_#{suffix}() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            INSERT INTO sync_versions (user_id, list, version)
            SELECT DISTINCT user_id, TG_ARGV[0], 1 FROM #{rows} WHERE user_id IS NOT NULL
            ON CONFLICT (user_id, list) DO UPDATE SET version = sync_versions.version + 1;
            RETURN NULL;
          END $$;
        SQL
      end
      TRIGGERS.each do |table, (list, events)|
        events.each do |event|
          rows = (event == "DELETE") ? "OLD TABLE AS old_rows" : "NEW TABLE AS new_rows"
          function = (event == "DELETE") ? "bump_sync_version_deleted" : "bump_sync_version_inserted"
          execute <<~SQL
            CREATE TRIGGER #{table}_#{event.downcase}_bump_sync_version AFTER #{event} ON #{table}
            REFERENCING #{rows}
            FOR EACH STATEMENT EXECUTE FUNCTION #{function}('#{list}')
          SQL
        end
      end
    end
  end

  def down
    safety_assured do
      TRIGGERS.each do |table, (_list, events)|
        events.each { |event| execute "DROP TRIGGER #{table}_#{event.downcase}_bump_sync_version ON #{table}" }
      end
      execute "DROP FUNCTION bump_sync_version_inserted(), bump_sync_version_deleted()"
    end
    drop_table :sync_versions
  end
end
