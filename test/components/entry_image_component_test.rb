require "test_helper"

class EntryImageComponentTest < ComponentTestCase
  setup do
    @entry = create_entry(feeds(:daring_fireball))
    create_image_row(
      provider: :entry_preview, provider_id: @entry.id, feed_id: @entry.feed_id,
      storage_path: "abc/abcdef123.jpg", placeholder_color: "aabbcc"
    )
    @entry.reload
  end

  test "renders the stored image with its placeholder colour" do
    with_env("UNIFIED_IMAGE_HOST" => "https://images.example.com") do
      output = render(App::EntryImageComponent.new(@entry)).to_s

      assert_equal 1, output.scan(%(class="entry-image")).count
      assert_includes output, %(data-src="https://images.example.com/abc/abcdef123.jpg")
      assert_includes output, "background-color: #aabbcc"
    end
  end
end
