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

  # A playlist feed mixes videos from many channels, so the channel avatar is
  # the entry's to resolve, not the feed's: provider_parent_id carries each
  # video's own channel, keyed the same way the embed_icon rows are.
  test "channel_image_record resolves the avatar row for the entry's own channel" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?playlist_id=PLcurated")
    entry = create_entry(feed)
    entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCvideochannel")

    row = Image.create!(
      provider: :embed_icon, provider_id: "UCvideochannel",
      url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )

    assert_equal row, entry.reload.channel_image_record
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

  test "processed_image tolerates a schemeless image host" do
    entry = create_entry(Feed.first)
    row = create_image_row(entry)

    with_env("UNIFIED_IMAGE_HOST" => "media.feedbin.org") do
      assert_equal "https://media.feedbin.org/#{row.storage_path}", entry.reload.processed_image
    end

    with_env("UNIFIED_IMAGE_HOST" => "http://minio.local:9000/images") do
      assert_equal "http://minio.local:9000/images/#{row.storage_path}", entry.reload.processed_image
    end
  end

  test "processed_image reads from the images row and nothing else" do
    entry = create_entry(Feed.first)
    row = create_image_row(entry)

    with_env("UNIFIED_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/#{row.storage_path}", entry.reload.processed_image
      assert entry.processed_image?
      assert_equal "aabbcc", entry.placeholder_color
    end

    with_env("UNIFIED_IMAGE_HOST" => nil) do
      assert_nil entry.reload.processed_image
    end
  end

  test "preview_image_data reads the row and is nil without one" do
    entry = create_entry(Feed.first)
    assert_nil entry.preview_image_data

    create_image_row(entry)
    entry.reload
    assert_equal "http://example.com/image-final.jpg", entry.preview_image_data["original_url"]
    assert_equal 542, entry.preview_image_data["width"]
    assert_equal 304, entry.preview_image_data["height"]
  end

  test "link_image reads from the images row and nothing else" do
    entry = create_entry(Feed.first)
    row = create_image_row(entry, provider: :entry_link_preview, url: "http://example.com/link.jpg")

    with_env("UNIFIED_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/#{row.storage_path}", entry.reload.link_image
      assert_equal "aabbcc", entry.link_image_placeholder_color
    end

    with_env("UNIFIED_IMAGE_HOST" => nil) do
      assert_nil entry.reload.link_image
    end
  end

  test "itunes_image reads the icon row and ignores the legacy url" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = create_feeds(users(:ben)).first
      entry = create_entry(feed)
      write_settings(entry, JSON.generate(JSON.generate({"media_image" => "https://old.example.com/abc/cover.jpg"})))

      assert_nil entry.itunes_image

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :entry_icon, provider_id: entry.id.to_s, feed_id: feed.id,
        url: "http://example.com/cover.jpg", variant: "200x200", kind: :cover_art,
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Entry.find(entry.id).itunes_image
    end
  end

  test "itunes_image is nil without an icon row" do
    feed = create_feeds(users(:ben)).first
    assert_nil create_entry(feed).itunes_image
  end

  # The legacy pointers stay in the JSON as inert data. No image method may
  # read them, whichever host is configured.
  test "legacy JSON alone renders nothing from any image method" do
    entry = create_entry(Feed.first)
    entry.update!(
      data: {
        "twitter_link_image_processed" => "https://bucket.s3.amazonaws.com/abc/link.jpg",
        "twitter_link_image_placeholder_color" => "ccddee",
        "itunes_image_processed" => "https://bucket.s3.amazonaws.com/abc/itunes.jpg"
      }
    )
    write_settings(entry, JSON.generate(JSON.generate({"media_image" => "https://bucket.s3.amazonaws.com/abc/cover.jpg"})))

    with_env("UNIFIED_IMAGE_HOST" => "https://images.example.com") do
      assert_nil entry.processed_image
      refute entry.processed_image?
      assert_nil entry.preview_image_data
      assert_nil entry.placeholder_color
      assert_nil entry.itunes_image
      assert_nil entry.link_image
      assert_nil entry.link_image_placeholder_color
    end
  end

  # Tweet receives the preview row: without one the tweet shows its link
  # preview, and a preview row suppresses it.
  test "tweet takes its image from the preview row" do
    entry = create_entry(Feed.first)
    entry.update!(
      data: {
        "tweet" => load_tweet("one"),
        "saved_pages" => {"https://example.com/p" => {"result" => {"ok" => true}}}
      }
    )
    create_image_row(entry, provider: :entry_link_preview, url: "http://example.com/link.jpg")

    fake_url = OpenStruct.new(expanded_url: URI.parse("https://example.com/p"), indices: [0, 10])
    tweet = Entry.find(entry.id).tweet
    tweet.main_tweet.stub :urls, [fake_url] do
      tweet.stub :link_tweet?, true do
        assert tweet.link_preview?, "without a preview row the link preview shows"
      end
    end

    create_image_row(entry)
    tweet = Entry.find(entry.id).tweet
    tweet.main_tweet.stub :urls, [fake_url] do
      tweet.stub :link_tweet?, true do
        refute tweet.link_preview?, "a preview row suppresses the link preview"
      end
    end
  end

  # Every shape an entry can hand us for an avatar, resolved against the
  # entry's own url. A plain relative path is the one that used to break:
  # the heuristic parser read "avatar.png" as a host.
  test "rebase_url with strict: reads every relative shape as a path" do
    entry = create_entry(feeds(:daring_fireball))
    entry.update!(url: "https://example.com/blog/post/1")

    assert_equal "https://example.com/avatar.png", entry.rebase_url("/avatar.png", strict: true)
    assert_equal "https://example.com/blog/post/avatar.png", entry.rebase_url("avatar.png", strict: true)
    assert_equal "https://example.com/blog/avatar.png", entry.rebase_url("../avatar.png", strict: true)
    assert_equal "https://cdn.example.net/avatar.png", entry.rebase_url("//cdn.example.net/avatar.png", strict: true)
    assert_equal "https://cdn.example.net/avatar.png", entry.rebase_url("https://cdn.example.net/avatar.png", strict: true)
    assert_equal "https://example.com/avatar.png", entry.rebase_url("  /avatar.png ", strict: true)
    assert_nil entry.rebase_url(nil, strict: true)
  end

  # Enclosures, chapters and content images go through the default reading,
  # where a url without a scheme is a host.
  test "rebase_url reads a scheme-less host as a host" do
    entry = create_entry(feeds(:daring_fireball))
    entry.update!(url: "https://example.com/blog/post/1")

    assert_equal "http://media.example.org/episode.mp3", entry.rebase_url("media.example.org/episode.mp3")
  end

  # One association, two kinds: a podcast episode's art and a micropost
  # author's avatar both live on entry_icon, and each reader sees only its
  # own kind, so neither view can render the other's picture.
  test "itunes_image and author_avatar_record split the entry_icon row by kind" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      art = create_entry(feeds(:daring_fireball))
      art_row = create_image_row(provider: :entry_icon, provider_id: art.id.to_s, feed_id: art.feed_id, kind: :cover_art, variant: "200x200", url: "http://example.com/art.jpg")
      avatar = create_entry(feeds(:daring_fireball))
      avatar_row = create_image_row(provider: :entry_icon, provider_id: avatar.id.to_s, feed_id: avatar.feed_id, kind: :avatar, variant: "200x200", url: "http://example.com/me.png")

      assert_equal "https://images.example.com/#{art_row.storage_path}", Entry.find(art.id).itunes_image
      assert_nil Entry.find(art.id).author_avatar_record
      assert_nil Entry.find(avatar.id).itunes_image
      assert_equal avatar_row, Entry.find(avatar.id).author_avatar_record
    end
  end

  test "with_list_associations preloads the entry icon row" do
    entry = create_entry(feeds(:daring_fireball))
    create_image_row(provider: :entry_icon, provider_id: entry.id.to_s, feed_id: entry.feed_id, kind: :avatar, variant: "200x200")
    entries = Entry.where(id: entry.id).with_list_associations.to_a

    statements = capture_sql { entries.each(&:author_avatar_record) }

    assert_empty statements.select { it.match?(/FROM "images"/i) }
    assert_not_nil entries.first.author_avatar_record
  end

  test "original_content reads the compressed column" do
    entry = saved_entry("<p>Old text.</p><p>New text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))

    assert_equal "<p>Old text.</p>", entry.reload.original_content
  end

  test "original_content survives later content changes" do
    entry = saved_entry("<p>First.</p>")
    second = "<p>First.</p><p>Second.</p>"
    entry.update!(content: second, compressed_original_content: OriginalContent.compress("<p>First.</p>", base: second))
    entry.update!(content: "<p>First.</p><p>Second.</p><p>Third.</p>")
    entry.update!(content: "<p>Only the fourth version.</p>")

    assert_equal "<p>First.</p>", entry.reload.original_content
  end

  test "a save that sets the compressed column with new content keeps the new value" do
    entry = saved_entry("<p>Old text.</p>")
    blob = OriginalContent.compress("<p>Old text.</p>", base: "<p>New text.</p>")
    entry.update!(content: "<p>New text.</p>", compressed_original_content: blob)

    assert_equal blob, entry.reload.compressed_original_content
  end

  test "a save without a content change keeps the stored value" do
    entry = saved_entry("<p>New text.</p>")
    blob = OriginalContent.compress("<p>Old text.</p>", base: entry.content)
    entry.update!(compressed_original_content: blob)
    entry.update!(title: "A new title")

    assert_equal blob, entry.reload.compressed_original_content
  end

  test "content changed outside callbacks makes original_content nil" do
    entry = saved_entry("<p>New text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))
    entry.update_columns(content: "<p>Rewritten without callbacks.</p>")

    entry.reload
    assert_nil entry.original_content
    assert_nil entry.content_diff
  end

  test "content changed to blank clears the stored value" do
    entry = saved_entry("<p>New text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))
    entry.update!(content: "")

    assert_nil entry.reload.compressed_original_content
  end

  test "content_diff marks the added text" do
    entry = saved_entry("<p>This is the text.</p>")
    entry.update!(
      content: "<p>This is the new text.</p>",
      compressed_original_content: OriginalContent.compress("<p>This is the text.</p>", base: "<p>This is the new text.</p>")
    )

    assert_match %r{<ins>new\s*</ins>}, entry.reload.content_diff
  end

  test "content_diff is nil without an original" do
    assert_nil saved_entry("<p>Text.</p>").content_diff
  end

  test "the raw source and media_image are no longer settings accessors" do
    refute_respond_to Entry.new, :newsletter
    refute_respond_to Entry.new, :media_image
  end

  test "settings reads the JSON string form that old rows hold" do
    @entry.save!
    write_settings(@entry, JSON.generate(JSON.generate({"embed_duration" => 647, "newsletter_from" => "News <news@example.com>"})))

    entry = Entry.find(@entry.id)

    assert_equal 647, entry.embed_duration
    assert_equal "News <news@example.com>", entry.newsletter_from
  end

  test "settings reads the object form that the backfill writes" do
    @entry.save!
    write_settings(@entry, JSON.generate({"embed_duration" => 647}))

    assert_equal 647, Entry.find(@entry.id).embed_duration
  end

  test "settings reads a NULL column as empty" do
    @entry.save!
    write_settings(@entry, nil)

    entry = Entry.find(@entry.id)

    assert_equal({}, entry.settings)
    assert_nil entry.embed_duration
  end

  test "a settings write drops the raw source and media_image" do
    @entry.save!
    write_settings(@entry, JSON.generate(JSON.generate({
      "newsletter" => "From: News <news@example.com>",
      "media_image" => "https://example.com/a.jpg",
      "newsletter_from" => "News <news@example.com>"
    })))

    Entry.find(@entry.id).update!(archived_images: true)

    assert_equal({"newsletter_from" => "News <news@example.com>", "archived_images" => true}, read_settings(@entry))
  end

  test "a settings write stores an object that SQL can read" do
    @entry.save!

    Entry.find(@entry.id).update!(embed_duration: 647)

    assert_equal "object", settings_type(@entry)
    assert_equal "647", Entry.uncached { Entry.connection.select_value("SELECT settings ->> 'embed_duration' FROM entries WHERE id = $1", "embed_duration", [@entry.id]) }
  end

  # A jsonb object cannot hold NUL; the old string form held it as an escape.
  test "a settings value with a NUL character saves without it" do
    @entry.save!

    Entry.find(@entry.id).update!(newsletter_from: "Ne\0ws <news@example.com>")

    assert_equal "News <news@example.com>", Entry.find(@entry.id).newsletter_from
  end

  private

  def write_settings(entry, json)
    Entry.connection.exec_update("UPDATE entries SET settings = $1::jsonb WHERE id = $2", "write_settings", [json, entry.id])
  end

  def raw_settings(entry)
    Entry.uncached { Entry.connection.select_value("SELECT settings::text FROM entries WHERE id = $1", "raw_settings", [entry.id]) }
  end

  def settings_type(entry)
    Entry.uncached { Entry.connection.select_value("SELECT jsonb_typeof(settings) FROM entries WHERE id = $1", "settings_type", [entry.id]) }
  end

  # The stored hash, whichever form the row holds.
  def read_settings(entry)
    value = JSON.parse(raw_settings(entry))
    value.is_a?(String) ? JSON.parse(value) : value
  end

  def saved_entry(content)
    @user.feeds.first.entries.create!(public_id: SecureRandom.hex, content: content)
  end

  # FactoryHelper's factory, keyed to an entry. It seeds a legacy url so the
  # read-path tests can prove the row's legacy pointer is ignored. Entry is
  # optional so callers that already pass provider_id/feed_id (entry_icon
  # rows keyed to two different entries in one test) fall through to the
  # plain factory instead.
  def create_image_row(entry = nil, provider: :entry_preview, url: "http://example.com/image.jpg", **overrides)
    return super(provider: provider, url: url, **overrides) if entry.nil?
    super(
      provider: provider,
      provider_id: entry.id,
      feed_id: entry.feed_id,
      url: url,
      data: {
        "legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/legacy.jpg",
        "final_url" => "http://example.com/image-final.jpg"
      },
      **overrides
    )
  end
end
