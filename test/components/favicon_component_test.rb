require "test_helper"

class FaviconComponentTest < ComponentTestCase

  setup do
    @feed = feeds(:daring_fireball)
  end

  test "generated favicon" do
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap"><span class="favicon-default favicon-mask" data-color-hash-seed="daringfireball.net"><span class="favicon-inner"></span></span></span>), output.to_s
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

  test "twitter user favicon" do
    tweet = load_tweet("one")
    @feed.update(options: {twitter_user: tweet["user"]})
    url = @feed.twitter_user.profile_image_uri_https(:original).to_s

    proxied = render FaviconComponent.new(feed: @feed)
    assert_includes proxied.to_s, "favicon-wrap icon-round"
    assert_includes proxied.to_s, "/files/icons/", "Deploy A only: the proxy until the copy lands"

    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      row = create_image_row(provider: :remote_file, provider_id: RemoteFile.fingerprint(url), feed_id: nil, kind: :avatar, url: url, variant: "200x200")
      output = render FaviconComponent.new(feed: @feed)

      assert_includes output.to_s, "https://images.example.com/#{row.storage_path}"
      refute_includes output.to_s, "/files/icons/"
    end
  end

  # Deploy 1 only: a proxy url with no row keeps today's derivation for its
  # shape. The branch goes with the proxy path in Deploy 2.
  test "feed icon" do
    @feed.custom_icon = "http://example.com/custom.png"
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap icon-round"><img alt="" onerror="this.onerror=null;this.src=&#39;http://test.host/assets/favicon-profile-default-65075e4958d19345a99f697e3b7eb70a82851108a33d28f85f70c0a3df02b4c5.png&#39;;" src="/files/icons/91a28cf86b9cdea1dcc6c7570f922135db424123/687474703a2f2f6578616d706c652e636f6d2f637573746f6d2e706e67" /></span>), output.to_s
  end

  test "a legacy proxy icon honors custom_icon_format square" do
    @feed.custom_icon = "http://example.com/custom.png"
    @feed.custom_icon_format = "square"
    output = render FaviconComponent.new(feed: @feed)
    assert_includes output.to_s, "favicon-wrap icon-square"
  end

  # A playlist feed mixes videos from many channels. The entry knows its own
  # channel (provider_parent_id); when that channel is not the feed's and its
  # avatar row exists, the entry renders that avatar rather than the feed's
  # icon. Round because the row's kind is avatar, read from the row.
  test "playlist entry renders the avatar of the channel its video belongs to" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?playlist_id=PLcurated")
      entry = create_entry(feed)
      entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCvideochannel")
      path = create_embed_icon("UCvideochannel").storage_path

      output = render FaviconComponent.new(feed: feed, entry: entry)

      assert_includes output.to_s, "https://images.example.com/#{path}"
      assert_includes output.to_s, "favicon-wrap icon-round"
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
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?playlist_id=PLcurated", host: "www.youtube.com")
      entry = create_entry(feed)
      entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCunharvested")
      create_favicon_row("www.youtube.com")

      output = render FaviconComponent.new(feed: Feed.find(feed.id), entry: entry)

      assert_includes output.to_s, "host-www-youtube-com"
    end
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
  # shared row before its own first harvest; the row's kind says round.
  test "channel avatar renders round from the row's kind" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      assert_nil feed.custom_icon

      create_image_row(provider: :embed_icon, provider_id: "UCabc", kind: :avatar, feed_id: nil, variant: "200x200")

      output = render FaviconComponent.new(feed: Feed.find(feed.id))

      assert_includes output.to_s, "favicon-wrap icon-round"
      refute_includes output.to_s, "twitter-profile-image"
      refute_includes output.to_s, "icon-format-"
    end
  end

  test "a feed's own cover art row renders square from the row's kind" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      create_image_row(
        provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id, kind: :cover_art,
        url: "http://example.com/show.jpg", variant: "200x200"
      )

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, "favicon-wrap icon-square"
    end
  end

  test "a feed's own avatar row renders round from the row's kind" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      create_image_row(
        provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id, kind: :avatar,
        url: "http://example.com/me.png", variant: "200x200"
      )

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, "favicon-wrap icon-round"
    end
  end

  test "favicon from the images row renders the unified url with the host class" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      row = create_favicon_row(@feed.host)

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_equal %(<span class="favicon-wrap"><span class="favicon host-daringfireball-net" style="background-image: url(https://images.example.com/#{row.storage_path});"></span></span>), output.to_s
    end
  end

  # The entry's host is lower-cased before the lookup and the class.
  test "pages article favicon from the images row" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      @feed.pages!
      entry = create_entry(@feed)
      entry.update!(url: "http://Example.com/article")
      row = create_favicon_row("example.com")

      output = render FaviconComponent.new(feed: @feed, entry: entry)

      assert_equal %(<span class="favicon-wrap"><span class="favicon host-example-com" style="background-image: url(https://images.example.com/#{row.storage_path});"></span></span>), output.to_s
    end
  end

  # The map is the collection-wide lookup; a caller that hands one in must
  # never trigger a per-entry query. provider_parent_id is set at create
  # from the entry's first url, so it is cleared here, and the feed is
  # loaded with its icon rows preloaded: what remains is the pages lookup.
  test "pages article favicon reads the map when one is given" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      @feed.pages!
      entry = create_entry(@feed)
      entry.update!(url: "http://example.com/article", provider_parent_id: nil)
      feed = Feed.includes(*Feed::ICON_PRELOADS).find(@feed.id)
      row = create_favicon_row("example.com")

      output = nil
      statements = capture_sql do
        output = render FaviconComponent.new(feed: feed, entry: entry, favicons: {"example.com" => row})
      end

      assert_includes output.to_s, row.storage_path
      assert_empty statements.select { it.match?(/FROM "images"|FROM "favicons"/i) }
    end
  end

  test "an images row with no unified host renders the generated favicon" do
    with_env("UNIFIED_IMAGE_HOST" => nil) do
      create_favicon_row(@feed.host)

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, "favicon-default"
    end
  end

  # No map and no images row: nothing to render but the default. The legacy
  # favicons row is gone, so this branch cannot fall through to anything.
  test "pages article with no images row renders the pages default" do
    @feed.pages!
    entry = create_entry(@feed)
    entry.update!(url: "http://nothing.example.com/article")

    output = render FaviconComponent.new(feed: @feed, entry: entry)

    assert_includes output.to_s, "favicon-saved"
  end

  private

  def create_embed_icon(channel_id)
    Image.create!(
      provider: :embed_icon, provider_id: channel_id, kind: :avatar,
      url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )
  end
end
