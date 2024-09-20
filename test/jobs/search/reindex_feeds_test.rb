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
      before = Search.client {_1.get_indexes_from_alias(Feed.table_name)}
      ReindexFeeds.new.perform
      Search.client { _1.refresh }

      after = Search.client {_1.get_indexes_from_alias(Feed.table_name)}
      results = Feed.search(@feeds.first.title)

      assert after.length == 1
      assert before != after
      assert results.first == @feeds.first
    end
  end
end