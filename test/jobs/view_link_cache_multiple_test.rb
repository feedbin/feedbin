require "test_helper"

class ViewLinkCacheMultipleTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @user = users(:new)
    @feeds = create_feeds(@user, 2)
    @inline_feed = @feeds.first
    @other_feed = @feeds.last
    @user.subscriptions.where(feed: @inline_feed).update_all(view_inline: true)
    @inline_entry = @inline_feed.entries.first
    @other_entry = @other_feed.entries.first
    UnreadEntry.create_from_owners(@user, @inline_entry)
    UnreadEntry.create_from_owners(@user, @other_entry)
  end

  test "enqueues a ViewLinkCache job per inline entry" do
    ViewLinkCache.jobs.clear

    ViewLinkCacheMultiple.new.perform(@user.id, [@inline_entry.id, @other_entry.id])

    assert_equal 1, ViewLinkCache.jobs.size
    args = ViewLinkCache.jobs.last["args"]
    assert_equal @inline_entry.fully_qualified_url, args[0]
    assert_kind_of Integer, args[1]
  end

  test "enqueues nothing when no entries are unread" do
    UnreadEntry.delete_all
    ViewLinkCache.jobs.clear

    ViewLinkCacheMultiple.new.perform(@user.id, [@inline_entry.id, @other_entry.id])

    assert_equal 0, ViewLinkCache.jobs.size
  end

  test "enqueues nothing when no subscriptions are inline" do
    @user.subscriptions.update_all(view_inline: false)
    ViewLinkCache.jobs.clear

    ViewLinkCacheMultiple.new.perform(@user.id, [@inline_entry.id, @other_entry.id])

    assert_equal 0, ViewLinkCache.jobs.size
  end
end
