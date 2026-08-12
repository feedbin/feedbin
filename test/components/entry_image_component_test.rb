require "test_helper"

class EntryImageComponentTest < ComponentTestCase
  setup do
    @entry = create_entry(feeds(:daring_fireball))
    @entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "storage_path" => "abc/abcdef123.webp",
      "width" => 542,
      "height" => 304,
      "placeholder_color" => "aabbcc"
    })
  end

  test "renders a single image outside development" do
    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      output = render(App::EntryImageComponent.new(@entry)).to_s

      assert_equal 1, output.scan(%(class="entry-image")).count
      assert_includes output, %(data-src="https://images.example.com/abc/abcdef123.webp")
      assert_includes output, "background-color: #aabbcc"
    end
  end

  test "stacks the legacy and R2 variants in development" do
    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
        output = render(App::EntryImageComponent.new(@entry)).to_s

        assert_equal 2, output.scan(%(class="entry-image")).count
        assert_includes output, %(data-src="https://bucket.s3.amazonaws.com/abc/abcdef.jpg")
        assert_includes output, %(data-src="https://images.example.com/abc/abcdef123.webp")
        assert_includes output, "s3 jpg"
        assert_includes output, "r2 webp"
      end
    end
  end

  test "renders a single image in development when only one variant exists" do
    @entry.update(image: @entry.image.except("storage_path"))

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
        output = render(App::EntryImageComponent.new(@entry)).to_s

        assert_equal 1, output.scan(%(class="entry-image")).count
        assert_includes output, %(data-src="https://bucket.s3.amazonaws.com/abc/abcdef.jpg")
        refute_includes output, "s3 jpg"
      end
    end
  end

  test "renders a single image in development when the R2 host is not configured" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      output = render(App::EntryImageComponent.new(@entry)).to_s

      assert_equal 1, output.scan(%(class="entry-image")).count
      assert_includes output, %(data-src="https://bucket.s3.amazonaws.com/abc/abcdef.jpg")
    end
  end
end
