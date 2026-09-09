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
        response = OpenStruct.new(etag: "1", last_modified: "2", download_fingerprint: "3", url: feed.feed_url)
        feed.crawl_data.save(response)
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

    test "does not crawl a flagged feed nobody has requested" do
      stale = standalone_feed("stale", requested_at: (StandaloneRetention::TTL + 1.day).ago)

      Schedule.new.perform

      refute_includes enqueued_feed_ids, stale.id
    end

    test "still crawls a flagged feed requested inside the TTL" do
      fresh = standalone_feed("fresh", requested_at: 1.day.ago)

      Schedule.new.perform

      assert_includes enqueued_feed_ids, fresh.id
    end

    # Schedule consults only `Subscription`; an Airshow feed reaches the
    # crawler solely through the standalone flag, so without this term a
    # listener silent for 90 days would stop getting new episodes.
    test "crawls a stale flagged feed that has an Airshow subscription" do
      stale = standalone_feed("podcast", requested_at: (StandaloneRetention::TTL + 1.day).ago)
      PodcastSubscription.create!(user: @user, feed: stale, status: :subscribed)

      Schedule.new.perform

      assert_includes enqueued_feed_ids, stale.id
    end

    private

    def standalone_feed(name, requested_at:)
      feed = Feed.create!(
        title: name,
        feed_url: "https://#{name}.example.com/feed",
        site_url: "https://#{name}.example.com"
      )
      feed.update_columns(standalone_request_at: requested_at)
      feed
    end

    def enqueued_feed_ids
      Downloader.jobs.map { |job| job["args"][0] }
    end
  end
end