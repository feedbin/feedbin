require "test_helper"

class CacheEntryViewsTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @entry = @entries.first
    flush_redis
  end

  test "enqueues ids" do
    cache = CacheEntryViews.new
    cache.perform(@entry.id)
    assert_equal([@entry.id.to_s], cache.dequeue_ids(CacheEntryViews::SET_NAME))
  end

  test "caches entries" do
    cache = CacheEntryViews.new
    cache.perform(@entry.id)
    CacheEntryViews.new.perform(nil, true)
  end
end
