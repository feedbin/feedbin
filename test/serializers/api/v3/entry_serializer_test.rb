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

  test "a revised entry carries its original content and diff" do
    entry = create_entry(@feed)
    original = entry.content
    entry.update!(content: original + "<p>A whole new paragraph.</p>", compressed_original_content: OriginalContent.compress(original, base: original + "<p>A whole new paragraph.</p>"))

    json = serialize(entry)

    assert_equal({content: original}, json[:original])
    assert_includes json[:diff][:html], "<ins>paragraph</ins>"
  end

  private

  def serialize(entry)
    Api::V3::EntrySerializer.new(Entry.with_list_associations.find(entry.id), feed: {}).to_h
  end
end
