require "test_helper"

class FeedRefresherTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Queues["feed_refresher_fetcher"].clear
    Feed.all.each do |feed|
      Feed.reset_counters(feed.id, :subscriptions)
    end
  end

  test "should enqueue feed_refresher_fetcher jobs" do
    assert_difference "Sidekiq::Queues['feed_refresher_fetcher'].count", Feed.count do
      FeedRefresher.new.tap do |job|
        def job.build_ids(*args)
          Feed.all.map(&:id)
        end
        job.perform(1, false)
      end
      Sidekiq::Queues["feed_refresher_fetcher"].each do |job|
        assert_equal(Feed.find(job["args"][0]).feed_url, job["args"][1])
      end
    end
  end

  test "should skip cache headers with force refresh" do
    feed = Feed.first
    feed.update etag: SecureRandom.uuid, last_modified: Time.now

    feed_refresher = FeedRefresher.new
    _, _, options = feed_refresher.build_arguments([feed.id], 0).first
    assert_not_nil(options[:etag])
    assert_not_nil(options[:last_modified])

    feed_refresher = FeedRefresher.new
    feed_refresher.force_refresh = true
    _, _, options = feed_refresher.build_arguments([feed.id], 0).first
    assert_nil(options[:etag])
    assert_nil(options[:last_modified])
  end
end
