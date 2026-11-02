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

  test "a newsletter's author is the sender" do
    @feed.update!(feed_type: :newsletter)
    entry = create_entry(@feed)
    entry.update!(newsletter_from: %("Ben" <ben@example.com>))

    json = serialize(entry)

    assert_equal "newsletter", json[:kind]
    assert_equal "Ben", json[:author]
  end

  test "a saved page" do
    @feed.update!(feed_type: :pages)

    assert_equal "page", serialize(create_entry(@feed))[:kind]
  end

  # Before this, the nil entry raised inside api_format and the rescue handed
  # back Mercury's HTML untouched.
  test "an extracted page is sanitized with its links resolved" do
    url = "https://example.com/story"
    page = {"url" => url, "result" => {"title" => "Story", "author" => "A", "content" => %(<p><a href="/more">more</a><script>1</script></p>)}}
    entry = create_entry(@feed)
    entry.update!(data: {"saved_pages" => {url => page}})

    extracted = serialize(entry)[:extracted]

    assert_equal 1, extracted.size
    assert_includes extracted.first[:content][:html], %(href="https://example.com/more")
    refute_includes extracted.first[:content][:html], "<script"
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

  test "include=changes adds the rendered edit, null for an unedited entry" do
    entry = create_entry(@feed)
    assert_nil serialize(entry, include: %w[changes])[:content][:changes]

    original = entry.content
    entry.update!(content: original + "<p>A whole new paragraph.</p>", compressed_original_content: OriginalContent.compress(original, base: original + "<p>A whole new paragraph.</p>"))

    json = serialize(entry, include: %w[changes])

    assert_equal [:html, :changes], json[:content].keys
    assert_includes json[:content][:changes][:html], "<ins>paragraph</ins>"
  end

  test "include=original_newsletter adds the email as sent, null for other kinds" do
    article = create_entry(@feed)
    assert_nil serialize(article, include: %w[original_newsletter])[:content][:original_newsletter]

    @feed.update!(feed_type: :newsletter)
    newsletter = create_entry(@feed)
    newsletter.update!(content: %(<style>@media (max-width: 600px) { .col { width: 100% } }</style><table><tr><td style="color: red">Hi</td></tr></table><script>alert(1)</script>))

    json = serialize(newsletter, include: %w[original_newsletter changes])

    assert_equal [:html, :changes, :original_newsletter], json[:content].keys
    html = json[:content][:original_newsletter][:html]
    assert_includes html, %(<td style="color: red">Hi</td>)
    assert_includes html, "max-width:10000px"
    refute_includes html, "<script"
  end

  private

  def serialize(entry, include: [])
    Api::V3::EntrySerializer.new(Entry.with_list_associations.find(entry.id), feed: {}, include: include).to_h
  end
end
