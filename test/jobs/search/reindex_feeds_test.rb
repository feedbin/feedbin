require "test_helper"

module Search
  class ReindexFeedsTest < ActiveSupport::TestCase
    setup do
      clear_search
      @user = users(:new)
      @feeds = create_feeds(@user)
      Feed.update_all(subscriptions_count: 101)
    end

    test "should reindex feeds" do
      before = Search.client {_1.get_indexes_from_alias(Search.index_name(Feed.table_name))}
      ReindexFeeds.new.perform
      Search.client { _1.refresh }

      after = Search.client {_1.get_indexes_from_alias(Search.index_name(Feed.table_name))}
      results = Feed.search(@feeds.first.title)

      assert after.length == 1
      assert before != after
      assert results.first == @feeds.first
    end

    # The each_slice(100) at the bottom of the job reads as batching, but the
    # dedup above it materialises every searchable feed as a full Feed first --
    # settings, options and crawl_data blobs included -- so the peak is the
    # whole corpus resident inside a long-lived worker.
    test "does not instantiate every searchable feed at once" do
      largest = 0
      subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |_, _, _, _, payload|
        largest = [largest, payload[:record_count]].max if payload[:class_name] == "Feed"
      end

      ReindexFeeds.stub_const(:SLICE_SIZE, 2) do
        ReindexFeeds.new.perform
      end

      assert_operator largest, :<=, 2, "the whole corpus was instantiated at once"
      assert_operator Feed.xml.count, :>, 2, "needs more feeds than a slice to be meaningful"
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    test "still excludes feeds that have stopped crawling" do
      broken = @feeds.first
      broken.update!(crawl_data: {error_count: 30})

      ReindexFeeds.new.perform
      Search.client { _1.refresh }

      refute_includes Feed.search(broken.title), broken
    end
  end
end