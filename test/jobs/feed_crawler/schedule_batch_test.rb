require "test_helper"

module FeedCrawler
  class ScheduleBatchTest < ActiveSupport::TestCase

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
        ScheduleBatch.new.tap do |job|
          def job.build_ids(*args)
            Feed.all.map(&:id)
          end
          job.perform(1, false)
        end
        Downloader.jobs.each do |job|
          feed = Feed.find(job["args"][0])
          assert_equal(feed.feed_url, job["args"][1])
          assert_equal(feed.subscriptions_count, job["args"][2])
          assert_equal(feed.crawl_data.to_h, job["args"][3].symbolize_keys)
        end
      end
    end

    test "skips enqueue for throttled feed" do
      ENV["THROTTLED_HOSTS"] = URI.parse(@feed.feed_url).host

      @feed.crawl_data.log_download
      @feed.save!

      assert_no_difference -> { Downloader.jobs.size } do
        ScheduleBatch.new.perform(batch, false)
      end

      travel (Throttle::TIMEOUT * 2).seconds do
        assert_difference -> { Downloader.jobs.size }, +1 do
          ScheduleBatch.new.perform(batch, false)
        end
      end
    end

    test "skips enqueue for feeds with errors" do
      @feed.crawl_data.download_error(Exception.new)
      @feed.save!

      assert_no_difference -> { Downloader.jobs.size } do
        ScheduleBatch.new.perform(batch, false)
      end

      @feed.crawl_data.clear!
      @feed.save!

      assert_difference -> { Downloader.jobs.size }, +1 do
        ScheduleBatch.new.perform(batch, false)
      end

    end

    test "enqueue for feeds with errors after backoff" do
      @feed.crawl_data.download_error(Exception.new)
      @feed.save!

      assert_no_difference -> { Downloader.jobs.size } do
        ScheduleBatch.new.perform(batch, false)
      end

      travel 2.hours do
        assert_difference -> { Downloader.jobs.size }, +1 do
          ScheduleBatch.new.perform(batch, false)
        end
      end
    end

    private

    def batch
      (@feed.id + SidekiqHelper::BATCH_SIZE / 2) / SidekiqHelper::BATCH_SIZE
    end
  end
end