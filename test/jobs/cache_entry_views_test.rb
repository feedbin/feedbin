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

    remaining_ids = CacheEntryViews.new.dequeue_ids(CacheEntryViews::SET_NAME)
    assert_nil remaining_ids, "Queue should be empty after processing"
  end

  # Fragment caching is off in the test environment, so this is about the key
  # the job asks for, not about what lands in the store. A bare `cached: true`
  # here warms a key the entry list never looks up: the warm pass and the live
  # render would disagree, and every view would render cold anyway.
  test "warms the key the entry list will look up" do
    Favicon.create!(host: @entry.feed.host, url: "http://example.com/a.png")
    CacheEntryViews.new.perform(@entry.id)

    captured = nil
    original = ApplicationController.method(:render)
    capture = ->(options = {}, *rest, &block) {
      captured = options if options.is_a?(Hash) && options[:partial] == "entries/entry"
      original.call(options, *rest, &block)
    }

    ApplicationController.stub(:render, capture) do
      CacheEntryViews.new.perform(nil, true)
    end

    assert_not_nil captured, "the job should render the entry partial as a collection"

    entry = captured[:collection].first
    favicons = captured[:locals][:favicons]

    assert_equal Favicon.for_entries([entry]), favicons
    assert_respond_to captured[:cached], :call
    assert_equal EntriesHelper.entries_cache_key(entry, favicons), captured[:cached].call(entry)
  end
end
