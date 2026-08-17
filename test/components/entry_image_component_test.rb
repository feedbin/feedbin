require "test_helper"

class EntryImageComponentTest < ComponentTestCase
  setup do
    @entry = create_entry(feeds(:daring_fireball))
    @entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "storage_path" => "abc/abcdef123.jpg",
      "width" => 542,
      "height" => 304,
      "placeholder_color" => "aabbcc"
    })
  end

  test "renders the stored image with its placeholder colour" do
    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      output = render(App::EntryImageComponent.new(@entry)).to_s

      assert_equal 1, output.scan(%(class="entry-image")).count
      assert_includes output, %(data-src="https://images.example.com/abc/abcdef123.jpg")
      assert_includes output, "background-color: #aabbcc"
    end
  end

  # The R2 host is what switches the read path over, so until it is set the
  # component has to keep serving the legacy object.
  test "falls back to the legacy url when the R2 host is not configured" do
    output = render(App::EntryImageComponent.new(@entry)).to_s

    assert_equal 1, output.scan(%(class="entry-image")).count
    assert_includes output, %(data-src="https://bucket.s3.amazonaws.com/abc/abcdef.jpg")
  end
end
