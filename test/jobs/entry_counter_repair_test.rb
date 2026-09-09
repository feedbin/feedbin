require "test_helper"

class EntryCounterRepairTest < ActiveSupport::TestCase
  setup do
    # Sidekiq's fake queues are global, so another file's jobs would count here.
    Sidekiq::Worker.clear_all

    @user = users(:ann)
    @other = users(:ben)
    @feed = Feed.create!(
      feed_url: "http://example.com/#{SecureRandom.hex}",
      host: "example.com",
      title: "Example"
    )
    @entry = bulk_create_entries(@feed, 1).first
  end

  def star(user)
    StarredEntry.create!(user_id: user.id, feed_id: @feed.id, entry_id: @entry.id, published: @entry.published)
  end

  def play(user)
    RecentlyPlayedEntry.create!(user_id: user.id, entry_id: @entry.id)
  end

  def queue(user)
    QueuedEntry.create!(user_id: user.id, feed_id: @feed.id, entry_id: @entry.id)
  end

  test "repairs an inflated starred counter" do
    star(@user)
    star(@other)
    StarredEntry.where(user_id: @user.id).delete_all
    assert_equal 2, @entry.reload.starred_entries_count

    EntryCounterRepair.new.perform([@entry.id])

    assert_equal 1, @entry.reload.starred_entries_count
  end

  test "repairs an inflated played counter" do
    play(@user)
    play(@other)
    RecentlyPlayedEntry.where(user_id: @user.id).delete_all

    EntryCounterRepair.new.perform([@entry.id])

    assert_equal 1, @entry.reload.recently_played_entries_count
  end

  # queued_entries_count is load-bearing for a future prune condition, so it
  # is repaired alongside the other two.
  test "repairs an inflated queued counter" do
    queue(@user)
    queue(@other)
    QueuedEntry.where(user_id: @user.id).delete_all
    assert_equal 2, @entry.reload.queued_entries_count

    EntryCounterRepair.new.perform([@entry.id])

    assert_equal 1, @entry.reload.queued_entries_count
  end

  # Drift runs both ways: activerecord-import skips callbacks entirely.
  test "repairs a deflated counter" do
    star(@user)
    @entry.update_columns(starred_entries_count: 0, queued_entries_count: 0)
    queue(@user)
    @entry.update_columns(queued_entries_count: 0)

    EntryCounterRepair.new.perform([@entry.id])

    @entry.reload
    assert_equal 1, @entry.starred_entries_count
    assert_equal 1, @entry.queued_entries_count
  end

  test "repairs all three columns in one pass" do
    star(@user)
    play(@user)
    queue(@user)
    @entry.update_columns(
      starred_entries_count: 9,
      recently_played_entries_count: 9,
      queued_entries_count: 9
    )

    EntryCounterRepair.new.perform([@entry.id])

    @entry.reload
    assert_equal 1, @entry.starred_entries_count
    assert_equal 1, @entry.recently_played_entries_count
    assert_equal 1, @entry.queued_entries_count
  end

  # recently_played_entries_count is nullable, and prune_entries compares it
  # with `= 0` -- a NULL there would pin the entry just as a stale count does.
  test "writes zero rather than null when nothing remains" do
    @entry.update_columns(recently_played_entries_count: nil)

    EntryCounterRepair.new.perform([@entry.id])

    assert_equal 0, @entry.reload.recently_played_entries_count
  end

  test "is idempotent" do
    star(@user)
    @entry.update_columns(starred_entries_count: 5)

    2.times { EntryCounterRepair.new.perform([@entry.id]) }

    assert_equal 1, @entry.reload.starred_entries_count
  end

  test "leaves entries outside the id list alone" do
    untouched = bulk_create_entries(@feed, 1).first
    untouched.update_columns(starred_entries_count: 7, queued_entries_count: 7)

    EntryCounterRepair.new.perform([@entry.id])

    untouched.reload
    assert_equal 7, untouched.starred_entries_count
    assert_equal 7, untouched.queued_entries_count
  end

  test "handles an empty id list" do
    assert_nothing_raised { EntryCounterRepair.new.perform([]) }
    assert_nothing_raised { EntryCounterRepair.new.perform(nil) }
  end

  test "ForFeeds repairs every entry in the given feeds" do
    star(@user)
    @entry.update_columns(starred_entries_count: 4)
    sibling = bulk_create_entries(@feed, 1).first
    sibling.update_columns(starred_entries_count: 3)

    Sidekiq::Testing.inline! { EntryCounterRepair::ForFeeds.new.perform([@feed.id]) }

    assert_equal 1, @entry.reload.starred_entries_count
    assert_equal 0, sibling.reload.starred_entries_count
  end

  test "enqueue splits large id lists into payload-sized chunks" do
    ids = (1..(EntryCounterRepair::CHUNK + 10)).to_a

    EntryCounterRepair.enqueue(ids)

    assert_equal 2, EntryCounterRepair.jobs.size
    assert_equal ids, EntryCounterRepair.jobs.flat_map { |job| job["args"].first }
  end

  test "ForFeeds ignores a blank feed list" do
    assert_nothing_raised { EntryCounterRepair::ForFeeds.new.perform([]) }
    assert_nothing_raised { EntryCounterRepair::ForFeeds.enqueue([]) }
    assert_equal 0, EntryCounterRepair::ForFeeds.jobs.size
  end

  test "ForFeeds.enqueue chunks large feed lists" do
    EntryCounterRepair::ForFeeds.enqueue((1..(EntryCounterRepair::CHUNK + 5)).to_a)

    assert_equal 2, EntryCounterRepair::ForFeeds.jobs.size
  end
end
