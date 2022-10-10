require "test_helper"

module FeedCrawler
  class TwitterScheduleTest < ActiveSupport::TestCase
    setup do
      @user = users(:ben)
      @feed = @user.feeds.first
      @keys = {"twitter_access_token" => "token", "twitter_access_secret" => "secret"}
      @feed.update(feed_type: :twitter)
      @user.update(@keys)
      flush_redis
    end

    test "feed gets scheduled" do
      assert_difference -> { TwitterDownloader.jobs.size }, +1 do
        TwitterSchedule.new.perform
      end

      args = [@feed.id, @feed.feed_url, [@keys]]
      job = TwitterDownloader.jobs.first
      assert_equal args, job["args"]
    end

    test "feed gets with passed user" do
      assert_difference -> { TwitterDownloaderCritical.jobs.size }, +1 do
        TwitterSchedule.new.enqueue_feed(@feed, @user)
      end

      args = [@feed.id, @feed.feed_url, [@keys]]
      job = TwitterDownloaderCritical.jobs.first
      assert_equal args, job["args"]
    end

    test "feed does not get scheduled because user doesn't match" do
      Feed.where(id: @feed.id).update_all(feed_type: :twitter_home, feed_url: "https://twitter.com?screen_name=bsaid")

      assert_no_difference -> { TwitterDownloader.jobs.size } do
        TwitterSchedule.new.perform
      end

      @user.update(twitter_screen_name: "bsaid")
      assert_difference -> { TwitterDownloader.jobs.size }, +1 do
        TwitterSchedule.new.perform
      end
    end
  end
end