# The lists the rest of v3 serves get versions too, with the same two trigger
# functions. Tables whose rows change in place (queue progress, a saved
# search's query, a playlist's title, an action) also fire on UPDATE.
class AddSyncVersionsForMoreLists < ActiveRecord::Migration[8.1]
  TRIGGERS = {
    "updated_entries" => ["updated", %w[INSERT DELETE]],
    "recently_read_entries" => ["recently_read", %w[INSERT DELETE]],
    "recently_played_entries" => ["recently_played", %w[INSERT UPDATE DELETE]],
    "queued_entries" => ["queue", %w[INSERT UPDATE DELETE]],
    "saved_searches" => ["saved_searches", %w[INSERT UPDATE DELETE]],
    "playlists" => ["playlists", %w[INSERT UPDATE DELETE]],
    "actions" => ["actions", %w[INSERT UPDATE DELETE]]
  }.freeze

  def up
    # CREATE TRIGGER takes a brief SHARE ROW EXCLUSIVE lock on each table.
    safety_assured do
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
    end
  end
end
