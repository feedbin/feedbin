require "test_helper"

class EntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    feed = @user.feeds.first
    @entry = feed.entries.build(
      public_id: SecureRandom.hex,
      content: "<p>#{Faker::Lorem.paragraph}</p>"
    )
  end

  test "should always have a published date" do
    assert_nil(@entry.published)
    @entry.save
    assert_not_nil(@entry.reload.published)
  end

  test "should cache id" do
    @entry.save
    assert_equal(@entry.content.length, $redis[:refresher].with { |redis| redis.get(@entry.public_id).to_i })
  end

  test "should create summary" do
    @entry.save
    assert_not_nil(@entry.reload.summary)
  end

  test "should update summary" do
    @entry.save
    summary = @entry.reload.summary
    @entry.update(content: "<p>#{Faker::Lorem.paragraph}</p>")
    assert_not_equal(summary, @entry.reload.summary)
  end

  test "should enqueue find_images" do
    flush_redis
    assert_difference -> { ImageCrawler::EntryImage.jobs.size }, +1 do
      @entry.save
      job = ImageCrawler::EntryImage.jobs.last
      assert_equal([@entry.reload.public_id], job["args"])
    end
  end

  test "should mark unread" do
    assert_difference "UnreadEntry.count", +1 do
      @entry.save
    end
  end

  test "should create queued entry" do
    assert_difference -> {QueuedEntry.count}, +1 do
      assert_difference -> {PodcastPushNotification.jobs.size}, +1 do
        @entry.save
      end
    end
  end

  test "should filter queued entry" do
    podcast_subscription = podcast_subscriptions(:ben_daring_fireball)
    podcast_subscription.download_filter_exclude!
    podcast_subscription.update(download_filter: "Filter me")

    assert_no_difference -> {QueuedEntry.count} do
      assert_no_difference -> {PodcastPushNotification.jobs.size} do
        @entry.update!(title: "filter Me")
      end
    end
  end

  test "should notify for bookmark" do
    podcast_subscription = podcast_subscriptions(:ben_daring_fireball)
    podcast_subscription.bookmarked!

    assert_difference -> {PodcastPushNotification.jobs.size}, +1 do
      @entry.save
    end
  end

  test "should not notify for hidden" do
    podcast_subscription = podcast_subscriptions(:ben_daring_fireball)
    podcast_subscription.hidden!

    assert_no_difference -> {PodcastPushNotification.jobs.size} do
      @entry.save
    end
  end

  test "should increment feed_stat" do
    assert_difference "FeedStat.count", +1 do
      @entry.save
    end
  end

  test "should update last_published_entry" do
    last_published_entry = @entry.feed.last_published_entry
    @entry.save
    assert_not_equal(last_published_entry, @entry.reload.feed.last_published_entry)
  end

  test "should get fully qualifed url" do
    @entry.url = "/test"
    assert_equal("http://daringfireball.net/test", @entry.fully_qualified_url)
  end

  test "should use JSON feed author" do
    @entry.update(data: {
      json_feed: {
        authors: [{name: "Robert Nemiroff"}, {name: "Jerry Bonnell"}]
      }
    })
    assert_equal("Robert Nemiroff and Jerry Bonnell", @entry.reload.author)
  end
end
