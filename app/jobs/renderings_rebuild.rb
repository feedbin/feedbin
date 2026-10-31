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

  # The table a full pass writes into, as a model so writes go through
  # upsert_all like the live table's.
  class NewTableRendering < ApplicationRecord
    self.table_name = "entry_renderings_new"
    self.primary_key = "entry_id"
  end

  MODELS = {LIVE_TABLE => EntryRendering, NEW_TABLE => NewTableRendering}.freeze

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
      connection.execute("DROP TABLE entry_renderings_new")
    end
    connection.execute("CREATE TABLE entry_renderings_new (LIKE entry_renderings INCLUDING ALL)")
    NewTableRendering.reset_column_information
  end

  SWAP_ATTEMPTS = 5

  # Ends a full pass: the new table replaces the live one. Rows the live table
  # gained or rewrote during the pass are not carried over: the pass's copy of
  # a rewritten row no longer matches its entry, an entry created during the
  # pass has no row, and the next read of either renders and stores it.
  #
  # The rename needs a lock that waits for in-flight reads of the live table,
  # and every new read queues behind it while it waits, so it gives up after a
  # second and tries again rather than holding up reads. Safe to run again
  # after a failure.
  def self.swap(attempts: SWAP_ATTEMPTS)
    pending = progress[:pending]
    raise "Jobs are still running (pending: #{pending})." if pending > 0
    connection = ActiveRecord::Base.connection
    raise "#{NEW_TABLE} does not exist. Start a full pass with rails renderings:rebuild." unless connection.table_exists?(NEW_TABLE)

    connection.execute("DROP TABLE IF EXISTS entry_renderings_old")
    attempt = 0
    begin
      attempt += 1
      connection.transaction do
        connection.execute("SET LOCAL lock_timeout = '1s'")
        connection.execute("ALTER TABLE entry_renderings RENAME TO entry_renderings_old")
        connection.execute("ALTER INDEX entry_renderings_pkey RENAME TO entry_renderings_old_pkey")
        connection.execute("ALTER TABLE entry_renderings_new RENAME TO entry_renderings")
        connection.execute("ALTER INDEX entry_renderings_new_pkey RENAME TO entry_renderings_pkey")
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempt >= attempts
      sleep swap_backoff(attempt)
      retry
    end
    EntryRendering.reset_column_information
    NewTableRendering.reset_column_information
    begin
      connection.execute("DROP TABLE entry_renderings_old")
    rescue ActiveRecord::StatementInvalid => exception
      Rails.logger.warn { "renderings swap: entry_renderings_old left in place (#{exception.message}); the next swap drops it" }
    end
    attempt
  end

  def self.swap_backoff(attempt)
    attempt * 2
  end

  # Entries per INSERT. A batch of newsletters with four versions each,
  # hex-escaped, would otherwise be one statement of hundreds of megabytes.
  def self.write_slice
    100
  end

  def perform(table, selector)
    raise ArgumentError, "not a renderings table: #{table.inspect}" unless TABLES.include?(table)
    counts = {rendered: 0, skipped: 0, failed: 0}
    entries(table, selector).find_each(batch_size: self.class.write_slice).each_slice(self.class.write_slice) do |slice|
      write(table, render(table, slice, counts))
    end
    finish(counts)
  end

  private

  def render(table, entries, counts)
    entries.filter_map do |entry|
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
  end

  # Only a pass over the live table reads the stored rows, to skip current ones.
  def entries(table, selector)
    scope = Entry.includes(:feed)
    scope = scope.preload(:rendering_record) if table == LIVE_TABLE
    if selector["range"]
      first, last = selector["range"]
      scope.where(id: first..last)
    else
      scope.where(id: selector["ids"])
    end
  end

  # One upsert per slice of entries.
  def write(table, rows)
    return if rows.empty?
    MODELS.fetch(table).upsert_all(rows.map { {entry_id: it.entry_id, version: it.version, blob: it.blob} }, unique_by: :entry_id)
  end

  def finish(counts)
    Sidekiq.redis do |redis|
      counts.each { |name, count| redis.incrby(self.class.key(name), count) }
      redis.decr(self.class.key("pending"))
    end
  end
end
