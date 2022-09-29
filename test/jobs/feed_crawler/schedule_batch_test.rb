require "test_helper"

module FeedCrawler
  class ScheduleBatchTest < ActiveSupport::TestCase
    setup do
      Sidekiq::Queues["feed_downloader"].clear
      Feed.all.each do |feed|
        Feed.reset_counters(feed.id, :subscriptions)
      end
    end

    test "should enqueue feed_downloader jobs" do
      assert_difference "Sidekiq::Queues['feed_downloader'].count", Feed.count do
        ScheduleBatch.new.tap do |job|
          def job.build_ids(*args)
            Feed.all.map(&:id)
          end
          job.perform(1, false)
        end
        Sidekiq::Queues["feed_downloader"].each do |job|
          feed = Feed.find(job["args"][0])
          assert_equal(feed.feed_url, job["args"][1])
          assert_equal(feed.subscriptions_count, job["args"][2])
          assert_equal(feed.crawl_data.to_h, job["args"][3].symbolize_keys)
        end
      end
    end
  end
end