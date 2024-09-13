require "test_helper"

class QueuedEntryLimiterTest < ActiveSupport::TestCase
  def setup
    @user = users(:ben)
    @user.update(podcast_download_limit: 2)

    @feed = @user.podcast_subscriptions.first.feed
    4.times { create_entry(@feed) }
    @entries = @feed.entries.order(published: :desc)
  end

  test "limits queued entries to the user\"s podcast download limit" do
    assert_difference -> { @user.queued_entries.count }, -2 do
      QueuedEntryLimiter.new.perform(@user.id)
    end

    assert_equal @entries.first(2).map(&:id).sort, @user.queued_entries.pluck(:entry_id).sort
  end

  test "respects the order of entries (most recent first)" do
    QueuedEntryLimiter.new.perform(@user.id)

    assert_equal @entries.first(2).map(&:id).sort, @user.queued_entries.pluck(:entry_id).sort
  end

  test "handles multiple feeds" do
    feed = feeds(:kottke)
    another_feed = @user.podcast_subscriptions.create!(feed: feed)
    entries = 4.times.map { create_entry(feed) }
    entries.each do |entry|
      QueuedEntry.create!(user: @user, feed: entry.feed, entry: entry)
    end

    assert_difference -> { @user.queued_entries.count }, -4 do
      QueuedEntryLimiter.new.perform(@user.id)
    end

    assert_equal 2, @user.queued_entries.where(feed: @feed).count
    assert_equal 2, @user.queued_entries.where(feed: feed).count
  end
end