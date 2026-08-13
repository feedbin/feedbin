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

  test "rebase_url returns a String for absolute urls" do
    result = @entry.rebase_url("http://example.com/podcast.mp3")
    assert_instance_of String, result
    assert_equal("http://example.com/podcast.mp3", result)
  end

  test "rebase_url returns a String for relative urls" do
    @entry.url = "http://daringfireball.net/episode"
    result = @entry.rebase_url("/podcast.mp3")
    assert_instance_of String, result
    assert_equal("http://daringfireball.net/podcast.mp3", result)
  end

  test "should use JSON feed author" do
    @entry.update(data: {
      json_feed: {
        authors: [{name: "Robert Nemiroff"}, {name: "Jerry Bonnell"}]
      }
    })
    assert_equal("Robert Nemiroff and Jerry Bonnell", @entry.reload.author)
  end

  test "tweet? is false for a non-tweet entry" do
    @entry.data = {"enclosure_url" => "http://example.com/a.mp3"}
    refute @entry.tweet?
    assert_nil @entry.tweet
  end

  test "tweet? is false when data is nil" do
    @entry.data = nil
    refute @entry.tweet?
    assert_nil @entry.tweet
  end

  test "accessing tweet on a non-tweet entry raises no exceptions" do
    @entry.data = {"enclosure_url" => "http://example.com/a.mp3"}

    raised = 0
    tp = TracePoint.new(:raise) do |t|
      raised += 1 if t.path.end_with?("app/models/tweet.rb", "app/models/entry.rb")
    end
    # Mirror the render path, which touches tweet?/tweet many times per entry.
    tp.enable { 10.times { @entry.tweet?; @entry.tweet } }
    tp.disable

    assert_equal 0, raised, "expected no exceptions building tweet for a non-tweet entry"
  end

  test "tweet? is true and tweet is built for a tweet entry" do
    @entry.data = {"tweet" => load_tweet("one")}
    assert @entry.tweet?
    assert_instance_of Tweet, @entry.tweet
  end

  test "tweet is memoized across calls" do
    @entry.data = {"tweet" => load_tweet("one")}
    assert_same @entry.tweet, @entry.tweet
  end

  test "processed_image prefers R2 when configured" do
    entry = create_entry(Feed.first)
    entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "storage_path" => "abc/abcdef123.webp",
      "width" => 542,
      "height" => 304,
      "placeholder_color" => "aabbcc"
    })

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/abc/abcdef123.webp", entry.processed_image
      assert entry.processed_image?
    end

    with_env("R2_IMAGE_HOST" => nil) do
      assert_equal "https://bucket.s3.amazonaws.com/abc/abcdef.jpg", entry.processed_image
    end
  end

  test "processed_image tolerates a schemeless R2 host" do
    entry = create_entry(Feed.first)
    entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "storage_path" => "abc/abcdef123.webp",
      "width" => 542,
      "height" => 304,
      "placeholder_color" => "aabbcc"
    })

    with_env("R2_IMAGE_HOST" => "media.feedbin.org") do
      assert_equal "https://media.feedbin.org/abc/abcdef123.webp", entry.processed_image
    end

    with_env("R2_IMAGE_HOST" => "http://minio.local:9000/images") do
      assert_equal "http://minio.local:9000/images/abc/abcdef123.webp", entry.processed_image
    end
  end

  test "processed_image ignores R2 host for legacy images without a storage_path" do
    entry = create_entry(Feed.first)
    entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "width" => 542,
      "height" => 304
    })

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://bucket.s3.amazonaws.com/abc/abcdef.jpg", entry.processed_image
    end
  end

  test "link_image falls back to legacy data keys" do
    entry = create_entry(Feed.first)
    entry.data ||= {}
    entry.data["twitter_link_image_processed"] = "https://bucket.s3.amazonaws.com/abc/abcdef-twitter.jpg"
    entry.data["twitter_link_image_placeholder_color"] = "ccddee"
    entry.save!

    assert_equal "https://bucket.s3.amazonaws.com/abc/abcdef-twitter.jpg", entry.link_image
    assert_equal "ccddee", entry.link_image_placeholder_color
  end

  test "processed_image reads from the images row" do
    entry = create_entry(Feed.first)
    row = create_image_row(entry)

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/#{row.storage_path}", entry.reload.processed_image
    end

    with_env("R2_IMAGE_HOST" => nil) do
      assert_equal "https://bucket.s3.amazonaws.com/abc/legacy.jpg", entry.reload.processed_image
    end

    assert entry.processed_image?
    assert_equal "aabbcc", entry.placeholder_color
  end

  test "preview_image_data prefers the row and falls back to legacy JSON" do
    entry = create_entry(Feed.first)
    entry.update(image: {"original_url" => "http://old.example.com/i.jpg", "width" => 100, "height" => 50})
    assert_equal 100, entry.preview_image_data["width"]

    create_image_row(entry)
    entry.reload
    assert_equal "http://example.com/image-final.jpg", entry.preview_image_data["original_url"]
    assert_equal 542, entry.preview_image_data["width"]
    assert_equal 304, entry.preview_image_data["height"]
  end

  test "link_image reads from the images row" do
    entry = create_entry(Feed.first)
    row = create_image_row(entry, provider: :entry_link_preview, url: "http://example.com/link.jpg")

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/#{row.storage_path}", entry.reload.link_image
    end

    with_env("R2_IMAGE_HOST" => nil) do
      assert_equal "https://bucket.s3.amazonaws.com/abc/legacy.jpg", entry.reload.link_image
    end

    assert_equal "aabbcc", entry.link_image_placeholder_color
  end

  test "itunes_image prefers the stored row over the legacy url" do
    with_env("R2_IMAGE_HOST" => "images.example.com", "ENTRY_IMAGE_HOST" => "legacy.example.com") do
      feed = create_feeds(users(:ben)).first
      entry = create_entry(feed)
      entry.update!(media_image: "https://old.example.com/abc/cover.jpg")

      assert_match "legacy.example.com", entry.itunes_image

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :entry_icon, provider_id: entry.id.to_s, feed_id: feed.id,
        url: "http://example.com/cover.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Entry.find(entry.id).itunes_image
    end
  end

  test "itunes_image is nil when there is neither a row nor a legacy url" do
    feed = create_feeds(users(:ben)).first
    assert_nil create_entry(feed).itunes_image
  end

  private

  def create_image_row(entry, provider: :entry_preview, url: "http://example.com/image.jpg")
    Image.create!(
      provider: provider,
      provider_id: entry.id.to_s,
      feed_id: entry.feed_id,
      url: url,
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for(url, "542x304"),
      width: 542, height: 304, bytesize: 12_345,
      placeholder_color: "aabbcc",
      data: {
        "legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/legacy.jpg",
        "final_url" => "http://example.com/image-final.jpg"
      }
    )
  end
end
