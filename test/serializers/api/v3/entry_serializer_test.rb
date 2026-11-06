require "test_helper"

class Api::V3::EntrySerializerTest < ActiveSupport::TestCase
  setup do
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example", site_url: "https://example.com")
  end

  test "an article is the default kind" do
    assert_equal "article", serialize(create_entry(@feed))[:kind]
  end

  test "a YouTube video carries its origin and channel picture" do
    entry = create_entry(@feed)
    entry.update!(data: {"youtube_video_id" => "Hq8Xw2Lk5dA"}, provider: :youtube, provider_id: "Hq8Xw2Lk5dA", provider_parent_id: "UCBJycsmduvYEL83R_U4JriQ")
    create_image_row(provider: :embed_icon, provider_id: "UCBJycsmduvYEL83R_U4JriQ", kind: :avatar)

    json = serialize(entry)

    assert_equal "video", json[:kind]
    assert_equal({provider: "youtube", id: "Hq8Xw2Lk5dA", channel_id: "UCBJycsmduvYEL83R_U4JriQ"}, json[:origin])
    assert_equal "avatar", json[:images][:icon][:kind]
  end

  test "a YouTube video entry lists its own video" do
    entry = create_entry(@feed)
    entry.update!(data: {"youtube_video_id" => "Hq8Xw2Lk5dA"}, provider: :youtube, provider_id: "Hq8Xw2Lk5dA")
    Embed.create!(source: :youtube_video, provider_id: "Hq8Xw2Lk5dA", parent_id: "UC1", data: {"snippet" => {"title" => "A video"}})

    videos = serialize(entry)[:videos]

    assert_equal ["Hq8Xw2Lk5dA"], videos.map { it[:id] }
    assert_equal "A video", videos.first[:title]
  end

  test "an entry without videos has an empty list" do
    assert_equal [], serialize(create_entry(@feed))[:videos]
  end

  test "a newsletter's author is the sender" do
    @feed.update!(feed_type: :newsletter)
    entry = create_entry(@feed)
    entry.update!(newsletter_from: %("Ben" <ben@example.com>))

    json = serialize(entry)

    assert_equal "newsletter", json[:kind]
    assert_equal "Ben", json[:author]
  end

  test "a micropost carries its author's handle; other kinds don't" do
    @feed.update!(options: {"image" => {"url" => "https://files.example.social/avatar.png", "link" => "https://example.social/@asymco", "title" => "Asymco"}})
    entry = create_entry(@feed)
    entry.update!(title: nil, data: {})

    json = serialize(entry)

    assert_equal "micropost", json[:kind]
    assert_equal "@asymco", json[:author_handle]
    assert_nil serialize(create_entry(@feed))[:author_handle]
  end

  test "a micropost without its own avatar uses the feed's avatar, but not a site icon" do
    @feed.update!(options: {"image" => {"url" => "https://files.example.social/avatar.png", "link" => "https://example.social/@asymco", "title" => "Asymco"}})
    entry = create_entry(@feed)
    entry.update!(title: nil, data: {})
    icon = create_image_row(provider: :feed_icon, provider_id: @feed.id.to_s, kind: :avatar)

    assert_equal "avatar", serialize(Entry.find(entry.id))[:images][:icon][:kind]

    icon.update!(kind: :site_icon)
    assert_nil serialize(Entry.find(entry.id))[:images][:icon]
  end

  test "a saved page" do
    @feed.update!(feed_type: :pages)

    assert_equal "page", serialize(create_entry(@feed))[:kind]
  end

  test "an extracted page is sanitized with its links resolved" do
    url = "https://example.com/story"
    page = {"url" => url, "result" => {"title" => "Story", "author" => "A", "content" => %(<p><a href="/more">more</a><script>1</script></p>)}}
    entry = create_entry(@feed)
    entry.update!(data: {"saved_pages" => {url => page}})

    extracted = serialize(entry)[:extracted]

    assert_equal url, extracted[:url]
    assert_includes extracted[:content][:html], %(href="https://example.com/more")
    refute_includes extracted[:content][:html], "<script"
    assert_nil serialize(create_entry(@feed))[:extracted]
  end

  test "serializes the preview image row" do
    entry = create_entry(@feed)
    fingerprint = SecureRandom.uuid
    create_image_row(provider: :entry_preview, provider_id: entry.id.to_s, kind: :poster, image_fingerprint: fingerprint, placeholder_color: "22436a")

    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      preview = serialize(entry)[:images][:preview]

      assert_equal "poster", preview[:kind]
      assert preview[:url].start_with?("https://images.example.com/")
      assert_equal "#22436a", preview[:placeholder_color]
      assert_equal "http://example.com/image.jpg", preview[:source_url]
      assert_equal fingerprint.delete("-"), preview[:fingerprint]
      assert_equal 12_345, preview[:size_in_bytes]
    end
  end

  test "content is a body object with nothing else unless asked" do
    json = serialize(create_entry(@feed))

    assert_equal [:html], json[:content].keys
    refute json.key?(:original)
    refute json.key?(:diff)
  end

  test "the feed is embedded only with expand=feed" do
    entry = create_entry(@feed)
    refute serialize(entry).key?(:feed)

    json = serialize(entry, expand: %w[feed], feed: {object: "feed", id: @feed.id})
    assert_equal :feed, json.keys.last
    assert_equal @feed.id, json[:feed][:id]
  end

  test "include=changes adds the rendered edit, null for an unedited entry" do
    entry = create_entry(@feed)
    assert_nil serialize(entry, expand: %w[changes])[:content][:changes]

    original = entry.content
    entry.update!(content: original + "<p>A whole new paragraph.</p>", compressed_original_content: OriginalContent.compress(original, base: original + "<p>A whole new paragraph.</p>"))

    json = serialize(entry, expand: %w[changes])

    assert_equal [:html, :changes], json[:content].keys
    assert_includes json[:content][:changes][:html], "<ins>paragraph</ins>"
  end

  test "include=original_newsletter adds the email as sent, null for other kinds" do
    article = create_entry(@feed)
    assert_nil serialize(article, expand: %w[original_newsletter])[:content][:original_newsletter]

    @feed.update!(feed_type: :newsletter)
    newsletter = create_entry(@feed)
    newsletter.update!(content: %(<style>@media (max-width: 600px) { .col { width: 100% } }</style><table><tr><td style="color: red">Hi</td></tr></table><script>alert(1)</script>))

    json = serialize(newsletter, expand: %w[original_newsletter changes])

    assert_equal [:html, :changes, :original_newsletter], json[:content].keys
    html = json[:content][:original_newsletter][:html]
    assert_includes html, %(<td style="color: red">Hi</td>)
    assert_includes html, "max-width:10000px"
    refute_includes html, "<script"
  end

  private

  def serialize(entry, expand: [], feed: nil)
    Api::V3::EntrySerializer.new(Entry.with_list_associations.find(entry.id), feed: feed, expand: expand).to_h
  end
end
