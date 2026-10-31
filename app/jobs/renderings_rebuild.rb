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
