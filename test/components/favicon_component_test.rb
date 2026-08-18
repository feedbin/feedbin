require "test_helper"

class FaviconComponentTest < ComponentTestCase

  setup do
    @feed = feeds(:daring_fireball)
  end

  test "generated favicon" do
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap"><span class="favicon-default favicon-mask" data-color-hash-seed="daringfireball.net"><span class="favicon-inner"></span></span></span>), output.to_s
  end

  test "cdn favicon" do
    favicon = Favicon.create!(url: "http://example.com/favicon.ico", host: @feed.host)
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap"><span class="favicon host-daringfireball-net" style="background-image: url(https://favicons.example.com/favicon.ico);"></span></span>), output.to_s
  end

  test "newsletter favicon" do
    @feed.newsletter!
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap collection-favicon"><svg width="14.0" height="10.0" class="favicon-newsletter"><use href="#favicon-newsletter"></use></svg></span>), output.to_s
  end

  test "pages default favicon" do
    @feed.pages!
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap collection-favicon"><svg width="13.0" height="12.0" class="favicon-saved"><use href="#favicon-saved"></use></svg></span>), output.to_s
  end

  test "pages article favicon" do
    @feed.pages!
    entry = create_entry(@feed)
    entry.update(url: "http://example.com/article")
    favicon = Favicon.create!(url: "http://example.com/favicon.ico", host: entry.hostname)

    output = render FaviconComponent.new(feed: @feed, entry: entry)
    assert_equal %(<span class="favicon-wrap"><span class="favicon host-example-com" style="background-image: url(https://favicons.example.com/favicon.ico);"></span></span>), output.to_s
  end

  test "twitter user favicon" do
    tweet = load_tweet("one")
    @feed.update(options: {twitter_user: tweet["user"]})
    output = render FaviconComponent.new(feed: @feed)
    favicon_markup = %(<span class="favicon-wrap twitter-profile-image"><img alt="" onerror="this.onerror=null;this.src=&#39;http://test.host/assets/favicon-profile-default-65075e4958d19345a99f697e3b7eb70a82851108a33d28f85f70c0a3df02b4c5.png&#39;;" src="/files/icons/38cdd03c8be8fcc27c7e933b093f0b4a7015c218/68747470733a2f2f7062732e7477696d672e636f6d2f70726f66696c655f696d616765732f3934363434383034353431353235363036342f626d4579337238412e6a7067" /></span>)
    assert_equal favicon_markup, output.to_s
  end

  test "feed icon" do
    @feed.custom_icon = "http://example.com/custom.png"
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap twitter-profile-image icon-format-round"><img alt="" onerror="this.onerror=null;this.src=&#39;http://test.host/assets/favicon-profile-default-65075e4958d19345a99f697e3b7eb70a82851108a33d28f85f70c0a3df02b4c5.png&#39;;" src="/files/icons/91a28cf86b9cdea1dcc6c7570f922135db424123/687474703a2f2f6578616d706c652e636f6d2f637573746f6d2e706e67" /></span>), output.to_s
  end

  # A playlist feed mixes videos from many channels. The entry knows its own
  # channel (provider_parent_id); when that channel is not the feed's and its
  # avatar row exists, the entry renders that avatar rather than the feed's
  # icon. Always round: an embed_icon row is a YouTube channel avatar.
  test "playlist entry renders the avatar of the channel its video belongs to" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?playlist_id=PLcurated")
      entry = create_entry(feed)
      entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCvideochannel")
      path = create_embed_icon("UCvideochannel").storage_path

      output = render FaviconComponent.new(feed: feed, entry: entry)

      assert_includes output.to_s, "https://images.example.com/#{path}"
      assert_includes output.to_s, "icon-format-round"
    end
  end

  # On a channel feed the entry's channel is the feed's channel, and the
  # feed's own resolution must keep winning -- its icon_image_record outranks
  # the shared channel avatar, and the entry branch must not undo that.
  test "channel feed entries keep the feed's own icon" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCownchannel")
      entry = create_entry(feed)
      entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCownchannel")
      create_embed_icon("UCownchannel")

      own_path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: feed.id.to_s, feed_id: feed.id,
        url: "http://example.com/own.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: own_path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(feed.id), entry: entry)

      assert_includes output.to_s, "https://images.example.com/#{own_path}"
    end
  end

  test "playlist entry with no avatar row falls through to the feed's resolution" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?playlist_id=PLcurated", host: "www.youtube.com")
    entry = create_entry(feed)
    entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCunharvested")
    favicon = Favicon.create!(url: "http://example.com/favicon.ico", host: "www.youtube.com")

    output = render FaviconComponent.new(feed: feed, entry: entry)

    assert_includes output.to_s, "host-www-youtube-com"
  end

  test "feed icon from the stored row is served directly, not through the proxy" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, "https://images.example.com/#{path}"
      refute_includes output.to_s, "/files/icons/",
        "a unified url is already on our own CDN and must not be wrapped in the signing proxy"
    end
  end

  # The branch cannot key on custom_icon: once the legacy store retires, a
  # row-backed feed has artwork and no custom_icon at all.
  test "feed icon renders from the row even with no custom_icon" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      assert_nil @feed.custom_icon

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, path
    end
  end

  # The stored avatar is already on our own CDN. Wrapping it in the signing
  # proxy would send a request we control back through a redirector built for
  # third-party urls.
  test "channel avatar from the stored row is served directly, not through the proxy" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png")
      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(feed.id))

      assert_includes output.to_s, "https://images.example.com/#{path}"
      refute_includes output.to_s, "/files/icons/"
    end
  end

  # A new subscription to a channel someone else already harvested finds the
  # shared row before its own first harvest writes custom_icon. An empty
  # format suffix is correct here: application.scss styles
  # .twitter-profile-image round and only .icon-format-square overrides it.
  test "channel avatar renders round when the feed has no custom_icon yet" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      assert_nil feed.custom_icon

      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(feed.id))

      assert_includes output.to_s, "twitter-profile-image"
      refute_includes output.to_s, "icon-format-square"
    end
  end
  private

  def create_embed_icon(channel_id)
    Image.create!(
      provider: :embed_icon, provider_id: channel_id,
      url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )
  end
end
