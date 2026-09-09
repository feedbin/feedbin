require "test_helper"

# A seam for observing the prune between batches: the hook runs after a
# batch's ids are resolved and before the next batch is queried, which is
# where a concurrent star, play or queue would land.
class MidPruneDeleter < EntryDeleter
  attr_accessor :before_batch

  def delete_entries(feed_id, entry_ids)
    before_batch&.call(entry_ids)
    super
  end
end

class EntryDeleterTest < ActiveSupport::TestCase
  setup do
    count = (5..16).to_a
    ENV["ENTRY_LIMIT"] = count.sample.to_s

    @user = users(:ben)
    @feed = @user.feeds.first
    # Fixture feed has an Airshow subscription, which prunable? refuses
    # outright; strip it so the pruning tests below can run (the guard is
    # tested separately).
    PodcastSubscription.where(feed_id: @feed.id).delete_all
    Feed.reset_counters(@feed.id, :subscriptions)
    @entries = bulk_create_entries(@feed, ENV["ENTRY_LIMIT"].to_i + count.sample)
  end

  teardown do
    ENV.delete("ENTRY_LIMIT")
  end

  test "should limit total entries" do
    assert @feed.entries.count > ENV["ENTRY_LIMIT"].to_i
    EntryDeleter.new.perform(@feed.id)
    assert_equal ENV["ENTRY_LIMIT"].to_i, @feed.reload.entries.count
  end

  test "should skip protected feeds" do
    @feed.update(protected: true)
    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should skip starred entries" do
    @entries.each do |entry|
      StarredEntry.create_from_owners(@user, entry)
    end
    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should skip queued entries" do
    @entries.each do |entry|
      QueuedEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: entry.id)
    end
    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  # The counter is the only thing prune_entries reads, so a queued entry whose
  # count drifted to zero would be deleted out from under the row.
  test "should skip a queued entry even when its counter says otherwise" do
    entry = @entries.min_by(&:published)
    QueuedEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: entry.id)
    assert_equal 1, entry.reload.queued_entries_count

    EntryDeleter.new.perform(@feed.id)

    assert Entry.exists?(entry.id), "a queued entry must survive the prune"
  end

  test "should remove UnreadEntries" do
    @entries.each do |entry|
      UnreadEntry.create_from_owners(@user, entry)
    end
    assert_difference -> { UnreadEntry.where(entry_id: entry_ids).count }, -removed_count do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should remove UpdatedEntries" do
    @entries.each do |entry|
      UpdatedEntry.create_from_owners(@user.id, entry)
    end
    assert_difference -> { UpdatedEntry.where(entry_id: entry_ids).count }, -removed_count do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should remove RecentlyPlayedEntries" do
    entry = @entries.first
    RecentlyPlayedEntry.create!(user: @user, entry: entry)

    EntryDeleter.new.delete_entries(@feed.id, entry.id)

    assert_equal 0, RecentlyPlayedEntry.where(entry_id: entry.id).count,
      "recently_played_entries has no foreign key, so a leftover row is an orphan"
  end

  test "should not partially delete when a statement fails" do
    entry = @entries.first
    UnreadEntry.create_from_owners(@user, entry)

    raises = ->(*) { raise ActiveRecord::StatementInvalid, "boom" }
    assert_raises(ActiveRecord::StatementInvalid) do
      Entry.stub(:where, raises) do
        EntryDeleter.new.delete_entries(@feed.id, entry.id)
      end
    end

    assert_equal 1, UnreadEntry.where(entry_id: entry.id).count,
      "the earlier deletes should roll back with the failed one"
  end

  test "should enqueue Search::SearchIndexRemove" do
    assert_difference "Search::SearchIndexRemove.jobs.size", +1 do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  # The images row is the only reference the collector needs. Legacy
  # pointers in the entry JSON are inert; nothing plucks them.
  test "should enqueue the collector for deleted entries and nothing for legacy objects" do
    flush_redis
    entry = @entries.first
    entry.update(
      published: 20.years.ago,
      image: {"processed_url" => "https://bucket.s3.amazonaws.com/abc/preview.jpg"},
      data: {"twitter_link_image_processed" => "https://bucket.s3.amazonaws.com/abc/link-legacy.jpg"}
    )

    queries = capture_sql { EntryDeleter.new.perform(@feed.id) }

    assert_equal 1, ImageGarbageCollector.jobs.size
    assert_includes ImageGarbageCollector.jobs.first["args"].first, entry.id
    assert_empty queries.grep(/twitter_link_image_processed|processed_url/), "the prune must not pluck legacy pointers"
  end

  # One collector job per feed-sized batch, not one per prune: a single job
  # over a backfill-sized id list is what exhausts the server-wide lock table.
  test "should slice image cleanup into batches" do
    flush_redis
    entry_ids = (1..2_500).to_a

    EntryDeleter.new.delete_entries(@feed.id, entry_ids)

    assert_equal 3, ImageGarbageCollector.jobs.size
    assert_equal entry_ids, ImageGarbageCollector.jobs.flat_map { it["args"].first }.sort
  end

  # A feed whose entries were pinned by stars or plays accumulates without
  # limit, so the delete set can be millions of rows by the time something
  # unpins them. These exercise the batched path with a slice of 2 rather than
  # by creating a realistic backlog.
  test "should prune a delete set that spans several batches" do
    limit = ENV["ENTRY_LIMIT"].to_i
    assert_operator removed_count, :>, 2, "setup must produce more than one batch at slice 2"

    EntryDeleter.new.prune_entries(@feed.id, limit, 2)

    assert_equal limit, @feed.reload.entries.count
  end

  test "should keep the newest entries across a multi-batch prune" do
    limit = ENV["ENTRY_LIMIT"].to_i
    newest = Entry.where(feed_id: @feed.id).order(published: :desc).limit(limit).pluck(:id)

    EntryDeleter.new.prune_entries(@feed.id, limit, 2)

    assert_equal newest.sort, @feed.reload.entries.pluck(:id).sort
  end

  test "should keep pinned entries across a multi-batch prune" do
    limit = ENV["ENTRY_LIMIT"].to_i
    starred, played = Entry.where(feed_id: @feed.id).order(published: :asc).limit(2).to_a
    StarredEntry.create_from_owners(@user, starred)
    RecentlyPlayedEntry.create!(user: @user, entry: played)

    EntryDeleter.new.prune_entries(@feed.id, limit, 2)

    assert Entry.exists?(starred.id), "a starred entry must survive a batched prune"
    assert Entry.exists?(played.id), "a recently played entry must survive a batched prune"
  end

  # The point of the batching: one bounded delete round per slice, rather than
  # one round whose pluck, IN list and Sidekiq payloads all scale with the
  # feed's backlog.
  test "should issue one delete round per batch" do
    flush_redis
    limit = ENV["ENTRY_LIMIT"].to_i
    expected_rounds = (removed_count / 2.0).ceil

    EntryDeleter.new.prune_entries(@feed.id, limit, 2)

    assert_equal expected_rounds, Search::SearchIndexRemove.jobs.size
  end

  # Collecting the delete set up front means it is a snapshot: anything that
  # pins an entry after the scan is invisible to it. The per-batch query has to
  # re-check the counters, or a star or a queue added while the prune is
  # running loses to it -- and queued_entries cascades on entry delete.
  test "should not delete an entry queued after the delete set is collected" do
    limit = ENV["ENTRY_LIMIT"].to_i
    delete_set = prunable_ids(@feed, limit)
    assert_operator delete_set.size, :>, 2, "setup must produce more than one batch at slice 2"

    target = nil
    deleter = MidPruneDeleter.new
    deleter.before_batch = ->(batch_ids) {
      next if target
      target = (delete_set - batch_ids).first
      QueuedEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: target)
    }

    deleter.prune_entries(@feed.id, limit, 2)

    assert target, "the hook never picked an entry from a later batch"
    assert Entry.exists?(target),
      "an entry queued mid-prune must survive, even though the delete set was collected before it was queued"
  end

  # The prune must scan the feed once and then work from primary keys. There is
  # no index that can serve `feed_id = ? AND id > ? ORDER BY id`, so a query
  # per batch means a full sort of the remaining rows per batch -- quadratic in
  # the feed's entry count. Pin it structurally: more batches must not mean
  # more feed_id scans.
  test "should not scan by feed_id once per batch" do
    shallow = feed_id_scans(prunable_feed(6), 2, 2)
    deep = feed_id_scans(prunable_feed(14), 2, 2)

    assert_operator shallow, :>, 0, "counted no feed_id scans at all -- the matcher stopped matching"
    assert_equal shallow, deep,
      "scans by feed_id grew with the number of batches -- the prune is quadratic in the feed's entry count"
  end

  test "should not prune a feed with an Airshow subscription" do
    PodcastSubscription.create!(user: @user, feed: @feed, status: :subscribed)

    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  # `hidden` is the column default, so a browsed-but-unfollowed show still
  # holds a row, and the guard must catch it too.
  test "should not prune a feed whose Airshow subscription is only hidden" do
    PodcastSubscription.create!(user: @user, feed: @feed, status: :hidden)

    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  # queued_entries cascades on entry delete, so pruning would silently empty
  # the queue and Airshow would delete the audio. update_column deflates the
  # counter (no callback repairs it), so prune_entries' own counter-cache
  # filter can't protect this entry -- only prunable?'s podcast guard can.
  test "should not empty a queue when the podcast guard is in place" do
    PodcastSubscription.create!(user: @user, feed: @feed, status: :subscribed)
    oldest = @feed.entries.order(published: :asc).first
    QueuedEntry.create!(user: @user, feed: @feed, entry: oldest)
    oldest.update_column(:queued_entries_count, 0)

    assert_no_difference -> { QueuedEntry.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  # The flag no longer exempts a feed from pruning -- it only sets depth, via
  # entry_limit.
  test "should prune a flagged feed" do
    @feed.update(standalone_request_at: 1.day.ago)

    EntryDeleter.new.perform(@feed.id)

    assert_equal ENV["ENTRY_LIMIT"].to_i, @feed.reload.entries.count
  end

  test "should still refuse a flagged podcast feed" do
    @feed.update(standalone_request_at: 1.day.ago)
    PodcastSubscription.create!(user: @user, feed: @feed, status: :subscribed)

    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should keep 400 for a feed with an active reader subscription" do
    ENV.delete("ENTRY_LIMIT")

    assert_equal 400, EntryDeleter.new.entry_limit(@feed)
  end

  test "should keep 400 for a flagged feed requested inside the TTL" do
    ENV.delete("ENTRY_LIMIT")
    @feed.subscriptions.update_all(active: false)
    @feed.update(standalone_request_at: 1.day.ago)

    assert_equal 400, EntryDeleter.new.entry_limit(@feed.reload)
  end

  test "should drop to 10 for a flagged feed nobody has requested" do
    ENV.delete("ENTRY_LIMIT")
    @feed.subscriptions.update_all(active: false)
    @feed.update(standalone_request_at: (StandaloneRetention::TTL + 1.day).ago)

    assert_equal 10, EntryDeleter.new.entry_limit(@feed.reload)
  end

  private

  # The entries prune_entries would delete, by the same rules it uses.
  def prunable_ids(feed, entry_limit)
    keep = Entry.where(feed_id: feed.id).order("published DESC").limit(entry_limit).pluck(:id)
    Entry.where(
      feed_id: feed.id,
      starred_entries_count: 0,
      recently_played_entries_count: 0,
      queued_entries_count: 0
    ).where.not(id: keep).pluck(:id)
  end

  # A bare feed of its own, so the batch count is exactly what the test asks
  # for rather than whatever the fixtures happen to hold.
  def prunable_feed(entry_count)
    url = Faker::Internet.url
    feed = Feed.create!(feed_url: url, host: URI(url).host, title: Faker::Lorem.sentence)
    bulk_create_entries(feed, entry_count)
    feed
  end

  # Counts the queries that filter on entries.feed_id, i.e. the ones that can
  # only be answered by reading the feed's rows.
  def feed_id_scans(feed, entry_limit, slice)
    scans = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"
      scans += 1 if payload[:sql].include?(%("entries"."feed_id" =))
    end

    EntryDeleter.new.prune_entries(feed.id, entry_limit, slice)
    scans
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def removed_count
    @entries.count - ENV["ENTRY_LIMIT"].to_i
  end

  def entry_ids
    @entries.map(&:id)
  end
end
