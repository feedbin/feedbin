require "test_helper"

class RenderingsRebuildTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    flush_redis
    @user = users(:new)
    @feed = @user.feeds.first || feeds(:daring_fireball)
  end

  def stale!(*entries)
    EntryRendering.where(entry_id: entries.map(&:id)).update_all(version: ContentFormatter::VERSION + 1)
  end

  test "perform renders a range into the live table and skips current rows" do
    stale, current = create_entry(@feed), create_entry(@feed)
    stale!(stale)
    RenderingsRebuild.new.perform("entry_renderings", "range" => [stale.id, current.id])
    assert_equal ContentFormatter::VERSION, EntryRendering.find(stale.id).version
    assert_equal({rendered: 1, skipped: 1, failed: 0}, RenderingsRebuild.progress.except(:pending))
  end

  test "perform writes an id list into the new table without touching the live one" do
    entry = create_entry(@feed)
    ActiveRecord::Base.connection.execute("CREATE TABLE entry_renderings_new (LIKE entry_renderings INCLUDING ALL)")
    before = EntryRendering.find(entry.id).blob
    RenderingsRebuild.new.perform("entry_renderings_new", "ids" => [entry.id, entry.id + 1_000_000])
    row = ActiveRecord::Base.connection.select_one("SELECT version, blob FROM entry_renderings_new WHERE entry_id = #{entry.id}")
    assert_equal ContentFormatter::VERSION, row["version"]
    assert_equal 1, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM entry_renderings_new").to_i
    assert_equal before, EntryRendering.find(entry.id).blob
  end

  test "perform writes in slices so a batch never builds one huge statement" do
    entries = 3.times.map { create_entry(@feed) }
    stale!(*entries)
    inserts = 0
    callback = ->(*, payload) { inserts += 1 if payload[:sql].start_with?(%(INSERT INTO "entry_renderings" )) }
    RenderingsRebuild.stub(:write_slice, 2) do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        RenderingsRebuild.new.perform("entry_renderings", "ids" => entries.map(&:id))
      end
    end
    assert_equal 2, inserts
    assert_equal 3, RenderingsRebuild.progress[:rendered]
  end

  test "a full start records the highest id the pass covers" do
    entry = create_entry(@feed)
    RenderingsRebuild.start(table: RenderingsRebuild::NEW_TABLE)
    assert_equal Entry.maximum(:id), Sidekiq.redis { it.get(RenderingsRebuild.key("max_id")) }.to_i
    assert_operator entry.id, :<=, Entry.maximum(:id)
  end

  test "perform rejects an unknown table" do
    assert_raises(ArgumentError) { RenderingsRebuild.new.perform("entries", "ids" => []) }
  end

  test "a failing entry is counted and the batch continues" do
    a, b = create_entry(@feed), create_entry(@feed)
    stale!(a, b)
    original = EntryRendering.method(:build)
    EntryRendering.stub(:build, ->(entry) { (entry.id == a.id) ? raise("boom") : original.call(entry) }) do
      RenderingsRebuild.new.perform("entry_renderings", "ids" => [a.id, b.id])
    end
    assert_equal ContentFormatter::VERSION, EntryRendering.find(b.id).version
    assert_equal 1, RenderingsRebuild.progress[:failed]
    assert_equal 1, RenderingsRebuild.progress[:rendered]
  end

  test "perform decrements pending" do
    Sidekiq.redis { it.set(RenderingsRebuild.key("pending"), 2) }
    RenderingsRebuild.new.perform("entry_renderings", "ids" => [])
    assert_equal 1, RenderingsRebuild.progress[:pending]
  end

  test "start enqueues one job per batch and refuses a second pass" do
    ids = (1..2_500).to_a
    assert_equal 3, RenderingsRebuild.start(ids: ids)
    assert_equal 3, RenderingsRebuild.jobs.size
    assert_equal({pending: 3, rendered: 0, skipped: 0, failed: 0}, RenderingsRebuild.progress)
    assert_raises(RuntimeError) { RenderingsRebuild.start(ids: ids) }
    assert_equal 3, RenderingsRebuild.start(ids: ids, force: true)
  end

  test "start without ids covers every id in ranges" do
    entry = create_entry(@feed)
    count = RenderingsRebuild.start(table: RenderingsRebuild::NEW_TABLE)
    assert_equal (Entry.maximum(:id) / RenderingsRebuild::BATCH.to_f).ceil, count
    args = RenderingsRebuild.jobs.map { it["args"] }
    assert args.all? { it.first == "entry_renderings_new" }
    assert args.any? { |_, selector| selector["range"].first <= entry.id && entry.id <= selector["range"].last }
  end
end

# Swapping renames tables, which a test transaction would roll back from under
# the assertions, so these run without one and clean up after themselves.
class RenderingsRebuildSwapTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Sidekiq::Worker.clear_all
    flush_redis
    @feed = feeds(:daring_fireball)
    @created = []
  end

  # Everything create_entry's callbacks write, or a later test in this worker
  # finds it: a leftover feed_stats row made "should increment feed stat"
  # update a row instead of creating one.
  teardown do
    connection = ActiveRecord::Base.connection
    connection.execute("DROP TABLE IF EXISTS entry_renderings_new")
    ids = @created.map(&:id)
    [EntryRendering, UnreadEntry, UpdatedEntry, QueuedEntry].each { it.where(entry_id: ids).delete_all }
    FeedStat.where(feed_id: @feed.id).delete_all
    Entry.where(id: ids).delete_all
    @feed.update_columns(last_published_entry: nil) if @feed.has_attribute?(:last_published_entry)
  end

  def entry
    create_entry(@feed).tap { @created << it }
  end

  test "swap refuses while jobs are pending" do
    Sidekiq.redis { it.set(RenderingsRebuild.key("pending"), 2) }
    RenderingsRebuild.prepare_table
    error = assert_raises(RuntimeError) { RenderingsRebuild.swap }
    assert_includes error.message, "pending: 2"
  end

  test "swap refuses without a new table" do
    assert_raises(RuntimeError) { RenderingsRebuild.swap }
  end

  test "swap copies rows written during the rebuild and renames the new table into place" do
    rebuilt = entry
    RenderingsRebuild.prepare_table
    RenderingsRebuild.new.perform("entry_renderings_new", "ids" => [rebuilt.id])
    arrived = entry
    Sidekiq.redis { it.set(RenderingsRebuild.key("pending"), 0); it.set(RenderingsRebuild.key("max_id"), rebuilt.id) }
    result = RenderingsRebuild.swap
    assert_equal 1, result[:copied]
    assert_equal [arrived.id, rebuilt.id].sort, EntryRendering.where(entry_id: @created.map(&:id)).pluck(:entry_id).sort
    connection = ActiveRecord::Base.connection
    refute connection.table_exists?("entry_renderings_new")
    refute connection.table_exists?("entry_renderings_old")
    assert_equal ["entry_renderings_pkey"], connection.select_values("SELECT indexname FROM pg_indexes WHERE tablename = 'entry_renderings'")
    assert_equal "e", connection.select_value("SELECT attstorage FROM pg_attribute WHERE attrelid = 'entry_renderings'::regclass AND attname = 'blob'")
    assert Entry.find(rebuilt.id).rendering.current_for?(rebuilt)
  end

  test "swap only scans rows above the pass's highest id, without a statement timeout" do
    rebuilt = entry
    RenderingsRebuild.prepare_table
    RenderingsRebuild.new.perform("entry_renderings_new", "ids" => [rebuilt.id])
    Sidekiq.redis { it.set(RenderingsRebuild.key("pending"), 0); it.set(RenderingsRebuild.key("max_id"), rebuilt.id) }
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { RenderingsRebuild.swap }
    carry_overs = statements.grep(/INSERT INTO entry_renderings_new/)
    assert_equal 2, carry_overs.size
    assert carry_overs.all? { it.include?("live.entry_id > #{rebuilt.id}") }
    assert statements.any? { it.match?(/SET LOCAL statement_timeout = 0/) }
  end

  test "swap refuses without the pass's highest id" do
    RenderingsRebuild.prepare_table
    Sidekiq.redis { it.set(RenderingsRebuild.key("pending"), 0) }
    assert_raises(RuntimeError) { RenderingsRebuild.swap }
  end

  test "swap succeeds when an earlier swap left the old table behind" do
    rebuilt = entry
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TABLE entry_renderings_old (LIKE entry_renderings)")
    RenderingsRebuild.prepare_table
    RenderingsRebuild.new.perform("entry_renderings_new", "ids" => [rebuilt.id])
    Sidekiq.redis { it.set(RenderingsRebuild.key("pending"), 0); it.set(RenderingsRebuild.key("max_id"), rebuilt.id) }
    RenderingsRebuild.swap
    refute connection.table_exists?("entry_renderings_old")
    assert_equal [rebuilt.id], EntryRendering.where(entry_id: rebuilt.id).pluck(:entry_id)
  ensure
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS entry_renderings_old")
  end

  test "prepare_table refuses to clobber an existing new table" do
    RenderingsRebuild.prepare_table
    assert_raises(RuntimeError) { RenderingsRebuild.prepare_table }
    RenderingsRebuild.prepare_table(force: true)
    assert ActiveRecord::Base.connection.table_exists?("entry_renderings_new")
  end
end
