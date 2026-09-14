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
    @feed.update!(custom_icon: "https://show.example.com/icon.jpg")
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

  # The legacy custom_icon is inert: a podcast with no row and no episode
  # art shows no artwork.
  test "media_image is nil when the show has only a legacy custom_icon" do
    @feed.update!(
      options: {"itunes_image" => "http://example.com/show.jpg"},
      custom_icon: "https://bucket.s3.amazonaws.com/abc/show.jpg",
      custom_icon_format: "square"
    )
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

  # Deploy A only: the proxy while the copy runs. Goes with the proxy.
  test "profile_image falls back to the proxy for a micropost with no row" do
    output = presenter_for(micropost_entry).profile_image

    assert_includes output, "favicon-wrap icon-round"
    assert_includes output, "/files/icons/"
  end

  test "profile_image renders the feed's icon for a micropost with no avatar at all" do
    output = presenter_for(micropost_entry(avatar: nil)).profile_image

    refute_includes output, "/files/icons/"
  end

  # A copied remote_file row for the same url serves a micropost whose own
  # row has not landed, and the replies dialog, whose OpenStruct has no row.
  test "profile_image resolves a micropost avatar by url when the entry has no row" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      entry = micropost_entry
      url = entry.micropost.author_avatar
      row = create_image_row(provider: :remote_file, provider_id: RemoteFile.fingerprint(url), feed_id: nil, kind: :avatar, url: url, variant: "200x200")

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

  # Tweets are the exception: no crawler, only rows copied from the proxy's
  # cache, resolved by url. The list hands the page's map down; one entry
  # on its own resolves directly.
  test "profile_image renders a tweet author's copied row from the map or by lookup" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      entry = tweet_entry
      url = entry.tweet_avatar_urls.first
      row = create_image_row(provider: :remote_file, provider_id: RemoteFile.fingerprint(url), feed_id: nil, kind: :avatar, url: url, variant: "200x200")

      with_map = EntryPresenter.new(entry, {avatars: {url => row.public_url}}, view).profile_image
      assert_includes with_map, "https://images.example.com/#{row.storage_path}"
      refute_includes with_map, "/files/icons/"

      alone = presenter_for(entry).profile_image
      assert_includes alone, "https://images.example.com/#{row.storage_path}"
    end
  end

  # Deploy A only: the proxy for a tweet avatar that has no row yet.
  test "profile_image falls back to the proxy for a tweet with no row" do
    output = EntryPresenter.new(tweet_entry, {avatars: {}}, view).profile_image

    assert_includes output, "/files/icons/"
  end
end
