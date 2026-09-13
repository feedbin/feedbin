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

  # A micropost author is a person, like the tweet branch above it in
  # profile_image -- both frame round, never the feed's icon_format.
  test "profile_image frames a micropost author's avatar round" do
    entry = @feed.entries.create!(
      title: nil,
      url: "https://micro.blog/someone/1",
      content: "<p>hi</p>",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex,
      published: Time.now,
      data: {"author" => {"name" => "Someone", "url" => "https://micro.blog/someone",
        "avatar" => "https://micro.blog/someone/avatar.jpg", "_microblog" => {"username" => "someone"}}}
    )

    output = presenter_for(entry).profile_image

    assert_includes output, "favicon-wrap icon-round"
    refute_includes output, "twitter-profile-image"
  end
end
