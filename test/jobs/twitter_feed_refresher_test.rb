require "test_helper"

class TwitterFeedRefresherTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @keys = {"twitter_access_token" => "token", "twitter_access_secret" => "secret"}
    @feed.update(feed_type: :twitter)
    @user.update(@keys)
  end

  test "feed gets scheduled" do
    Sidekiq::Worker.clear_all
    assert_difference "Sidekiq::Queues['feed_refresher_fetcher_critical'].count", +1 do
      TwitterFeedRefresher.new.perform
    end

    args = [@feed.id, @feed.feed_url, [@keys]]
    job = Sidekiq::Queues["feed_refresher_fetcher_critical"].first
    assert_equal args, job["args"]
    assert(job.key?("at"), "job should have an 'at' parameter")
  end

  test "feed gets with passed user" do
    Sidekiq::Worker.clear_all

    assert_difference "Sidekiq::Queues['feed_refresher_fetcher_critical'].count", +1 do
      TwitterFeedRefresher.new.enqueue_feed(@feed, @user)
    end

    args = [@feed.id, @feed.feed_url, [@keys]]
    job = Sidekiq::Queues["feed_refresher_fetcher_critical"].first
    assert_equal args, job["args"]
    assert_not(job.key?("at"), "job should not have an 'at' parameter")
  end

  test "feed does not get scheduled because user doesn't match" do
    Feed.class_eval do
      def self.readonly_attributes
        []
      end
    end
    @feed.update(feed_type: :twitter_home, feed_url: "https://twitter.com?screen_name=bsaid")

    Sidekiq::Worker.clear_all
    assert_no_difference "Sidekiq::Queues['feed_refresher_fetcher_critical'].count" do
      TwitterFeedRefresher.new.perform
    end

    @user.update(twitter_screen_name: "bsaid")
    assert_difference "Sidekiq::Queues['feed_refresher_fetcher_critical'].count", +1 do
      TwitterFeedRefresher.new.perform
    end
  end
end
