require "test_helper"

# The bulk-delete and bulk-insert paths that skip counter caches. Each one
# owes its entries an EntryCounterRepair; without it the count stays wrong
# and EntryDeleter#prune_entries reads a lie.
class EntryCounterDriftTest < ActiveSupport::TestCase
  setup do
    @user = users(:ann)
    @keeper = users(:ben)
    @feed = Feed.create!(
      feed_url: "http://example.com/#{SecureRandom.hex}",
      host: "example.com",
      title: "Example"
    )
    @entry = bulk_create_entries(@feed, 1).first
  end

  def counters
    @entry.reload
    [@entry.starred_entries_count, @entry.recently_played_entries_count, @entry.queued_entries_count]
  end

  def truth
    [
      StarredEntry.where(entry_id: @entry.id).count,
      RecentlyPlayedEntry.where(entry_id: @entry.id).count,
      QueuedEntry.where(entry_id: @entry.id).count
    ]
  end

  test "destroying a user leaves every counter correct" do
    StarredEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: @entry.id, published: @entry.published)
    RecentlyPlayedEntry.create!(user_id: @user.id, entry_id: @entry.id)
    QueuedEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: @entry.id)

    StarredEntry.create!(user_id: @keeper.id, feed_id: @feed.id, entry_id: @entry.id, published: @entry.published)

    assert_equal [2, 1, 1], counters

    Sidekiq::Testing.inline! do
      Stripe::Customer.stub(:retrieve, Minitest::Mock.new.expect(:delete, nil)) do
        @user.destroy
      end
    end

    assert_equal [1, 0, 0], truth
    assert_equal truth, counters, "counters must match the rows that survive the destroy"
  end

  # An account that starred fifty things must repair fifty entries, not every
  # entry in the fifty feeds those entries came from.
  test "destroying an ordinary user repairs its exact entries, not whole feeds" do
    StarredEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: @entry.id, published: @entry.published)
    bystander = bulk_create_entries(@feed, 5).last
    Sidekiq::Worker.clear_all

    Stripe::Customer.stub(:retrieve, Minitest::Mock.new.expect(:delete, nil)) { @user.destroy }

    queued = EntryCounterRepair.jobs.flat_map { |job| job["args"].first }
    assert_equal [@entry.id], queued
    refute_includes queued, bystander.id, "an untouched entry in the same feed must not be repaired"
    assert_equal 0, EntryCounterRepair::ForFeeds.jobs.size
  end

  # Past the limit, carrying exact ids stops paying for itself: an account
  # that large has starred a big share of its feeds, so whole-feed repair
  # costs about the same and the payloads stay bounded.
  test "destroying a very large user falls back to feed-based repair" do
    StarredEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: @entry.id, published: @entry.published)
    Sidekiq::Worker.clear_all

    User.stub(:counter_cache_id_limit, 0) do
      Stripe::Customer.stub(:retrieve, Minitest::Mock.new.expect(:delete, nil)) { @user.destroy }
    end

    assert_equal 0, EntryCounterRepair.jobs.size, "exact ids must not be carried past the limit"
    assert_equal [[@feed.id]], EntryCounterRepair::ForFeeds.jobs.map { |job| job["args"].first }
  end

  test "ForFeeds repairs every entry in the feeds it is given" do
    entries = bulk_create_entries(@feed, 3)
    entries.each { |entry| entry.update_columns(starred_entries_count: 5) }

    Sidekiq::Testing.inline! { EntryCounterRepair::ForFeeds.new.perform([@feed.id]) }

    entries.each { |entry| assert_equal 0, entry.reload.starred_entries_count }
  end

  test "clearing recently played leaves the counter correct" do
    RecentlyPlayedEntry.create!(user_id: @user.id, entry_id: @entry.id)
    RecentlyPlayedEntry.create!(user_id: @keeper.id, entry_id: @entry.id)
    assert_equal 2, counters[1]

    Sidekiq::Testing.inline! do
      RecentlyPlayedEntry.clear_for_user(@user.id)
    end

    assert_equal 0, RecentlyPlayedEntry.where(user_id: @user.id).count
    assert_equal 1, counters[1]
  end

  test "the queued entry limiter leaves the counter correct" do
    QueuedEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: @entry.id)
    QueuedEntry.create!(user_id: @keeper.id, feed_id: @feed.id, entry_id: @entry.id)
    assert_equal 2, counters[2]

    @user.update_columns(settings: (@user.settings || {}).merge("podcast_download_limit" => 0))

    Sidekiq::Testing.inline! do
      QueuedEntryLimiter.new.perform(@user.id)
    end

    assert_equal 0, QueuedEntry.where(user_id: @user.id).count
    assert_equal 1, counters[2]
  end

  # QueuedEntry.import runs with on_duplicate_key_ignore, and
  # index_queued_entries_on_user_id_and_entry_id is unique, so a subscriber
  # who already holds the episode is skipped. Incrementing by the number
  # attempted rather than the number inserted inflates the counter every time
  # that happens.
  test "queueing an episode counts rows inserted, not rows attempted" do
    subscription = PodcastSubscription.create!(
      user_id: @user.id, feed_id: @feed.id, status: :subscribed
    )
    assert subscription.persisted?

    entry = bulk_create_entries(@feed, 1).first
    entry.update_columns(data: {"enclosure_url" => "http://example.com/a.mp3", "enclosure_type" => "audio/mpeg"})

    # Already queued: the import must skip it and the counter must not move
    # past the one real row.
    QueuedEntry.create!(user_id: @user.id, feed_id: @feed.id, entry_id: entry.id)
    entry.update_columns(queued_entries_count: 1)

    entry.send(:mark_as_unplayed)

    assert_equal 1, QueuedEntry.where(entry_id: entry.id).count
    assert_equal 1, entry.reload.queued_entries_count
  end
end
