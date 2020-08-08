require "test_helper"

class FeedRefresherTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Queues["feed_downloader"].clear
    Feed.all.each do |feed|
      Feed.reset_counters(feed.id, :subscriptions)
    end
  end

  test "should enqueue feed_downloader jobs" do
    assert_difference "Sidekiq::Queues['feed_downloader'].count", Feed.count do
      FeedRefresher.new.tap do |job|
        def job.build_ids(*args)
          Feed.all.map(&:id)
        end
        job.perform(1, false)
      end
      Sidekiq::Queues["feed_downloader"].each do |job|
        assert_equal(Feed.find(job["args"][0]).feed_url, job["args"][1])
      end
    end
  end

end
