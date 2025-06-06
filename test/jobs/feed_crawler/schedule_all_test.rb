require "test_helper"

module FeedCrawler
  class ScheduleTest < ActiveSupport::TestCase

    setup do
      flush_redis
      @user = users(:ben)
      @feed = @user.feeds.first
      Feed.all.each do |feed|
        Feed.reset_counters(feed.id, :subscriptions)
      end
    end

    test "should enqueue feed_downloader jobs" do
      assert_difference -> { Downloader.jobs.size }, Feed.count do
        Schedule.new.perform
        Downloader.jobs.each do |job|
          feed = Feed.find(job["args"][0])
          assert_equal(feed.feed_url, job["args"][1])
          assert_equal(feed.subscriptions_count, job["args"][2])
          assert_equal(feed.crawl_data.to_h, job["args"][3].symbolize_keys)
        end
      end
    end

    test "skips enqueue for throttled feed" do
      hosts = Feed.all.pluck(:host)
      ENV["THROTTLED_HOSTS"] = hosts.map {"#{it}=1"}.join(" ")

      Feed.all.each do |feed|
        feed.crawl_data.log_download
        feed.save!
      end

      assert_no_difference -> { Downloader.jobs.size } do
        Schedule.new.perform
      end

      travel (Throttle::TIMEOUT * 2).seconds do
        assert_difference -> { Downloader.jobs.size }, Feed.count do
          Schedule.new.perform
        end
      end
    end

    test "skips enqueue for feeds with errors" do
      Feed.all.each do |feed|
        feed.crawl_data.download_error(Exception.new)
        feed.save!
      end


      assert_no_difference -> { Downloader.jobs.size } do
        Schedule.new.perform
      end

      Feed.all.each do |feed|
        feed.crawl_data.clear!
        feed.save!
      end
      flush_redis

      assert_difference -> { Downloader.jobs.size }, +Feed.count do
        Schedule.new.perform
      end

    end

    test "enqueue for feeds with errors after backoff" do
      Feed.all.each do |feed|
        feed.crawl_data.download_error(Exception.new)
        feed.save!
      end

      assert_no_difference -> { Downloader.jobs.size } do
        Schedule.new.perform
      end

      travel 2.hours do
        assert_difference -> { Downloader.jobs.size }, Feed.count do
          Schedule.new.perform
        end
      end
    end
  end
end