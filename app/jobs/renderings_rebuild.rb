# Re-renders stored entry renderings in the background, one job per batch of
# entries. A scoped pass (a feed, a date) writes into entry_renderings in
# place and skips rows already current; a full pass writes every entry into
# entry_renderings_new, which RenderingsRebuild.swap renames into place.
#
#   RenderingsRebuild.start(ids: Entry.where(feed_id: 1).pluck(:id))
#   RenderingsRebuild.start(table: RenderingsRebuild::NEW_TABLE)
#   RenderingsRebuild.progress  # => {pending: 0, rendered: 123, skipped: 4, failed: 0}
#
# Normally started with rails renderings:rebuild. A pass is done at pending: 0.
class RenderingsRebuild
  include Sidekiq::Worker
  sidekiq_options queue: :backfill

  LIVE_TABLE = "entry_renderings"
  NEW_TABLE = "entry_renderings_new"
  TABLES = [LIVE_TABLE, NEW_TABLE].freeze
  BATCH = 1_000
  COUNTERS = %w[pending rendered skipped failed].freeze
  TTL = 30.days.to_i

  def self.key(name)
    "renderings_rebuild:#{name}"
  end

  def self.progress
    values = Sidekiq.redis { |redis| COUNTERS.map { |name| redis.get(key(name)) } }
    COUNTERS.map(&:to_sym).zip(values.map(&:to_i)).to_h
  end

  # A second start while jobs are still out would reset the counters under
  # them, and their decrements would end the new pass early.
  def self.start(ids: nil, table: LIVE_TABLE, force: false)
    pending = progress[:pending]
    raise "A pass is still running (pending: #{pending}). Pass force: true to start over." if pending > 0 && !force

    selectors = if ids
      ids.each_slice(BATCH).map { {"ids" => it} }
    else
      (1..Entry.maximum(:id).to_i).step(BATCH).map { {"range" => [it, it + BATCH - 1]} }
    end

    Sidekiq.redis do |redis|
      COUNTERS.each { |name| redis.set(key(name), 0, ex: TTL) }
      redis.set(key("pending"), selectors.size, ex: TTL)
    end
    selectors.each_slice(1_000) do |slice|
      Sidekiq::Client.push_bulk("class" => self, "args" => slice.map { [table, it] })
    end
    selectors.size
  end

  # The empty table a full pass writes into.
  def self.prepare_table(force: false)
    connection = ActiveRecord::Base.connection
    if connection.table_exists?(NEW_TABLE)
      raise "#{NEW_TABLE} already exists. Pass force: true to drop it and start over." unless force
      connection.execute("DROP TABLE #{NEW_TABLE}")
    end
    connection.execute("CREATE TABLE #{NEW_TABLE} (LIKE #{LIVE_TABLE} INCLUDING ALL)")
    connection.execute("ALTER TABLE #{NEW_TABLE} ALTER COLUMN blob SET STORAGE EXTERNAL")
  end

  # Ends a full pass: the new table replaces the live one. Entries created
  # while the pass ran were rendered into the live table by their own save,
  # so those rows are carried over first, once in bulk and once more under a
  # lock that holds off writes (reads continue) for the moment of the rename.
  # A row the live table rewrote during the pass keeps the pass's copy; its
  # CRC no longer matches and the next read re-renders it.
  def self.swap
    pending = progress[:pending]
    raise "Jobs are still running (pending: #{pending})." if pending > 0
    connection = ActiveRecord::Base.connection
    raise "#{NEW_TABLE} does not exist. Start a full pass with rails renderings:rebuild." unless connection.table_exists?(NEW_TABLE)

    carry_over = <<~SQL
      INSERT INTO #{NEW_TABLE} (entry_id, version, blob)
      SELECT live.entry_id, live.version, live.blob FROM #{LIVE_TABLE} live
      WHERE live.version = #{ContentFormatter::VERSION.to_i}
      AND NOT EXISTS (SELECT 1 FROM #{NEW_TABLE} new WHERE new.entry_id = live.entry_id)
    SQL
    copied = connection.exec_update(carry_over)
    connection.transaction do
      connection.execute("LOCK TABLE #{LIVE_TABLE} IN EXCLUSIVE MODE")
      copied += connection.exec_update(carry_over)
      connection.execute("ALTER TABLE #{LIVE_TABLE} RENAME TO entry_renderings_old")
      connection.execute("ALTER INDEX entry_renderings_pkey RENAME TO entry_renderings_old_pkey")
      connection.execute("ALTER TABLE #{NEW_TABLE} RENAME TO #{LIVE_TABLE}")
      connection.execute("ALTER INDEX entry_renderings_new_pkey RENAME TO entry_renderings_pkey")
    end
    connection.execute("DROP TABLE entry_renderings_old")
    EntryRendering.reset_column_information
    {copied: copied, rows: EntryRendering.count}
  end

  def perform(table, selector)
    raise ArgumentError, "not a renderings table: #{table.inspect}" unless TABLES.include?(table)
    counts = {rendered: 0, skipped: 0, failed: 0}
    rows = entries(selector).filter_map do |entry|
      if table == LIVE_TABLE && entry.rendering_record&.current_for?(entry)
        counts[:skipped] += 1
        next
      end
      rendering = EntryRendering.build(entry)
      counts[:rendered] += 1
      rendering
    rescue => exception
      counts[:failed] += 1
      ErrorService.notify(
        error_class: "RenderingsRebuild",
        error_message: "rendering failed",
        parameters: {entry_id: entry.id, exception: exception}
      )
      nil
    end
    write(table, rows)
    finish(counts)
  end

  private

  def entries(selector)
    scope = Entry.includes(:feed).preload(:rendering_record)
    if selector["range"]
      first, last = selector["range"]
      scope.where(id: first..last)
    else
      scope.where(id: selector["ids"])
    end
  end

  # One statement per batch. Bytea goes in as escaped text: quoting the raw
  # bytes fails on null bytes.
  def write(table, rows)
    return if rows.empty?
    connection = ActiveRecord::Base.connection
    values = rows.map do |row|
      "(#{row.entry_id.to_i}, #{row.version.to_i}, #{connection.quote(connection.escape_bytea(row.blob))}::bytea)"
    end
    connection.execute(<<~SQL)
      INSERT INTO #{table} (entry_id, version, blob) VALUES #{values.join(",")}
      ON CONFLICT (entry_id) DO UPDATE SET version = EXCLUDED.version, blob = EXCLUDED.blob
    SQL
  end

  def finish(counts)
    Sidekiq.redis do |redis|
      counts.each { |name, count| redis.incrby(self.class.key(name), count) }
      redis.decr(self.class.key("pending"))
    end
  end
end
