require "test_helper"

class EntryPresenterTest < ActionView::TestCase
  setup do
    @feed = feeds(:daring_fireball)
  end

  def presenter_for(entry)
    EntryPresenter.new(entry, nil, view)
  end

  def entry_with(attributes)
    @feed.entries.create!({
      title: "Episode 1",
      url: "http://example.com/episode-1",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex
    }.merge(attributes))
  end

  # A saved page has no entry of its own, so its URL is the base for links.
  # Before this, the nil entry raised inside api_format and the rescue handed
  # back Mercury's HTML untouched.
  test "extracted_articles sanitizes a saved page and resolves its links" do
    url = "https://example.com/story"
    page = {"url" => url, "result" => {"title" => "Story", "domain" => "example.com", "author" => "A", "content" => %(<p><a href="/more">more</a><script>1</script></p>)}}
    entry = entry_with(data: {"saved_pages" => {url => page}})
    articles = presenter_for(entry).extracted_articles
    assert_equal 1, articles.size
    assert_includes articles.first[:content], %(href="https://example.com/more")
    refute_includes articles.first[:content], "<script"
  end

  # Feedbin Notifier still asks for ?private; it gets the API rendering.
  test "app_content is the api rendering" do
    entry = entry_with(content: %(<p><a href="/link"><img src="/img.png"></a></p>))
    presenter = presenter_for(entry)
    assert_equal presenter.api_content, presenter.app_content
    assert_match %r{src="http://[^"]+/img.png"}, presenter.app_content
  end

  test "content serves the stored web rendering" do
    entry = entry_with(content: "<p>live</p>")
    EntryRendering.where(entry_id: entry.id).update_all(blob: EntryRendering.encode({web: "<p>stored</p>", api: "<p>stored api</p>"}, content: entry.content, crc: EntryRendering.inputs_crc(entry)))
    presenter = presenter_for(Entry.find(entry.id))
    assert_equal "<p>stored</p>", presenter.content
    assert_equal "<p>stored api</p>", presenter.api_content
    assert_equal "<p>stored api</p>", presenter.app_content
  end

  test "newsletter_content wraps the stored full rendering" do
    @feed.update!(feed_type: :newsletter)
    entry = entry_with(content: "<html><body><p>n</p></body></html>")
    EntryRendering.where(entry_id: entry.id).update_all(blob: EntryRendering.encode({web: "", api: "", full: "<p>stored full</p>"}, content: entry.content, crc: EntryRendering.inputs_crc(entry)))
    presenter = presenter_for(Entry.find(entry.id))
    assert_includes presenter.newsletter_content, "<p>stored full</p>"
    assert_includes presenter.newsletter_content, "<style>"
  end

  test "newsletter_from reads the sender from settings" do
    entry = entry_with(newsletter_from: "\"Example News\" <news@example.com>")

    from = presenter_for(entry).newsletter_from

    assert_equal "Example News", from.name
    assert_equal "news@example.com", from.address
  end

  test "newsletter_from keeps a sender with no display name" do
    from = presenter_for(entry_with(newsletter_from: "news@example.com")).newsletter_from

    assert_equal "news@example.com", from.name
    assert_nil from.address
  end

  test "newsletter_from is nil when the entry has no sender" do
    assert_nil presenter_for(entry_with({})).newsletter_from
  end

  test "newsletter_from is nil when the sender is blank" do
    assert_nil presenter_for(entry_with(newsletter_from: " ")).newsletter_from
    assert_nil presenter_for(entry_with(newsletter_from: "<>")).newsletter_from
  end

  test "newsletter_from ignores the old Mailgun payload in data" do
    entry = entry_with(data: {"newsletter" => {"data" => {"from" => "Old <old@example.com>"}}})

    assert_nil presenter_for(entry).newsletter_from
  end

  # media_image is entry.itunes_image || entry.feed.icon_url. Distinct
  # values on each side so a regression that returned the show's icon here
  # would visibly fail rather than coincidentally match.
  test "media_image prefers the episode's artwork over the show's" do
    create_image_row(provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id, storage_path: "abc/show.jpg", kind: :cover_art)
    entry = entry_with({})
    create_image_row(
      provider: :entry_icon, provider_id: entry.id.to_s, feed_id: @feed.id,
      storage_path: "abc/cover.jpg", kind: :cover_art
    )

    with_env("UNIFIED_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/abc/cover.jpg", presenter_for(entry).media_image
    end
  end

  test "media_image falls back to the show's feed_icon row when the episode has none" do
    @feed.update!(options: {"itunes_image" => "http://example.com/show.jpg"})
    path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
    create_image_row(
      provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id,
      url: "http://example.com/show.jpg", variant: "200x200", storage_path: path
    )
    entry = entry_with({})

    with_env("UNIFIED_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/#{path}", presenter_for(Entry.find(entry.id)).media_image
    end
  end

  # A podcast with no row and no episode art shows no artwork.
  test "media_image is nil when the show has no row" do
    @feed.update!(options: {"itunes_image" => "http://example.com/show.jpg"})
    entry = entry_with({})

    assert_nil presenter_for(entry).media_image
  end

  def micropost_entry(avatar: "https://micro.blog/someone/avatar.jpg")
    @feed.entries.create!(
      title: nil,
      url: "https://micro.blog/someone/1",
      content: "<p>hi</p>",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex,
      published: Time.now,
      data: {"author" => {"name" => "Someone", "url" => "https://micro.blog/someone",
        "avatar" => avatar, "_microblog" => {"username" => "someone"}}}
    )
  end

  # A micropost author is a person, like the tweet branch above it in
  # profile_image -- both frame round, never the feed's icon_format. The
  # row is the source; it is on our CDN and must not go through the proxy.
  test "profile_image renders a micropost author's avatar row round" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      entry = micropost_entry
      row = create_image_row(provider: :entry_icon, provider_id: entry.id.to_s, feed_id: entry.feed_id, kind: :avatar, variant: "200x200")

      output = presenter_for(Entry.find(entry.id)).profile_image

      assert_includes output, "favicon-wrap icon-round"
      assert_includes output, "https://images.example.com/#{row.storage_path}"
      refute_includes output, "/files/icons/"
    end
  end

  test "profile_image serves a micropost avatar with no row through camo" do
    entry = micropost_entry
    output = presenter_for(entry).profile_image

    assert_includes output, "favicon-wrap icon-round"
    assert_includes output, Camo.url(entry.micropost.author_avatar)
    refute_includes output, "/files/icons/"
  end

  test "profile_image renders the feed's icon for a micropost with no avatar at all" do
    output = presenter_for(micropost_entry(avatar: nil)).profile_image

    assert_includes output, "favicon-default"
    refute_includes output, "icon-round"
  end

  # Another post's row for the same url serves a micropost whose own row
  # has not landed, and the replies dialog, whose OpenStruct has no row.
  test "profile_image resolves a micropost avatar by url when the entry has no row" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      entry = micropost_entry
      url = entry.micropost.author_avatar
      row = create_image_row(provider: :entry_icon, provider_id: "other-post", feed_id: nil, kind: :avatar, url: url, variant: "200x200", data: {"preset" => "micropost_avatar"})

      output = presenter_for(Entry.find(entry.id)).profile_image

      assert_includes output, "https://images.example.com/#{row.storage_path}"
      refute_includes output, "/files/icons/"
    end
  end

  def tweet_entry
    @feed.entries.create!(
      title: nil, url: "https://twitter.com/someone/status/1", content: "<p>hi</p>",
      public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: Time.now,
      data: {"tweet" => load_tweet("one")}
    )
  end

  # Tweets have no crawler: their avatars resolve through the icons path,
  # which serves the copy moved out of remote_files, or camo.
  test "profile_image renders a tweet author through the icons path" do
    entry = tweet_entry
    output = presenter_for(entry).profile_image

    assert_includes output, TwitterAvatar.path(entry.tweet.main_tweet.user.profile_image_uri_https(:original))
  end

  test "api_original keeps the old shape with the original content and current values" do
    content = "<p>Old text.</p><p>New text.</p>"
    fingerprint = SecureRandom.uuid
    entry = @feed.entries.create!(
      public_id: SecureRandom.hex,
      title: "Current title",
      author: "Current author",
      url: "https://example.com/post",
      entry_id: "entry-1",
      fingerprint: fingerprint,
      content: content,
      data: {"media" => []}
    )
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: content))
    entry.reload

    result = presenter_for(entry).api_original

    assert_equal %i[author content title url entry_id published data fingerprint], result.keys
    assert_equal "<p>Old text.</p>", result[:content]
    assert_equal ["Current author", "Current title", "https://example.com/post", "entry-1"], result.values_at(:author, :title, :url, :entry_id)
    assert_equal entry.published, result[:published]
    assert_equal({"media" => []}, result[:data])
    assert_equal fingerprint, result[:fingerprint]
  end

  test "api_original is nil without an original" do
    entry = @feed.entries.create!(public_id: SecureRandom.hex, content: "<p>Text.</p>")

    assert_nil presenter_for(entry).api_original
  end
end
