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

    refute_includes output, "/files/icons/"
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
end
