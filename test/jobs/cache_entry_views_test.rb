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

  # About the key the job asks for, not what lands in the store (fragment
  # caching is off in test). The feed must be Pages: only that branch reads
  # the favicons map, so any other feed would pass vacuously.
  test "warms the key the entry list will look up" do
    feed = Feed.create!(feed_url: "https://pages.example/x", host: "pages.example", title: "P", feed_type: :pages)
    entry = create_entry(feed)
    entry.update!(url: "http://site.example.com/article")
    Favicon.create!(host: "site.example.com", url: "http://example.com/a.png")

    CacheEntryViews.new.perform(entry.id)

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
    refute_empty favicons, "fixture must exercise the Pages branch where favicons is load-bearing"
    assert_respond_to captured[:cached], :call
    assert_equal EntriesHelper.entries_cache_key(entry, favicons), captured[:cached].call(entry)
  end
end
