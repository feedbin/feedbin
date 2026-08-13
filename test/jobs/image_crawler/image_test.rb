require "test_helper"

module ImageCrawler
  class ImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    test "ignores unknown attributes" do
      image = Image.new("id" => "abc", "attribute_from_the_future" => "value")
      assert_equal "abc", image.id
    end

    test "sets known attributes" do
      image = Image.new("id" => "abc", "preset_name" => "primary", "image_urls" => ["http://example.com/a.jpg"])
      assert_equal "primary", image.preset_name
      assert_equal ["http://example.com/a.jpg"], image.image_urls
    end

    test "unified? requires an opted-in preset and the R2 bucket env" do
      image = Image.new_with_attributes(id: "a", preset_name: "primary", image_urls: [], provider: 2, provider_id: 1)
      refute image.unified?

      with_env("R2_BUCKET_IMAGES" => "images-test") do
        assert image.unified?
        podcast = Image.new_with_attributes(id: "a", preset_name: "podcast", image_urls: [], provider: 0, provider_id: 1)
        refute podcast.unified?
      end
    end

    test "storage_path is derived from original_url" do
      image = Image.new_with_attributes(id: "a", preset_name: "primary", image_urls: [], provider: 2, provider_id: 1, original_url: "http://example.com/a.jpg")
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304"), image.storage_path
      assert_equal ::Image.url_fingerprint_for("http://example.com/a.jpg", "542x304"), image.url_fingerprint
    end

    test "send_to_feedbin includes unified metadata when unified" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        image = Image.new_with_attributes(
          id: "a", preset_name: "primary", image_urls: [],
          provider: ::Image.providers[:entry_preview], provider_id: 1,
          original_url: "http://example.com/a.jpg", final_url: "http://example.com/a.jpg",
          storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
          width: 542, height: 304, bytesize: 9_999, placeholder_color: "aabbcc"
        )
        image.send_to_feedbin

        _, payload = EntryImage.jobs.last["args"]
        assert_equal image.storage_path, payload["storage_path"]
        assert_equal 9_999,              payload["bytesize"]
        assert_equal "entry_preview",    payload["provider"]
      end
    end

    test "send_to_feedbin keeps the legacy payload shape when not unified" do
      image = Image.new_with_attributes(
        id: "a", preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg", final_url: "http://example.com/a.jpg",
        storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
        width: 542, height: 304, placeholder_color: "aabbcc"
      )
      image.send_to_feedbin

      _, payload = EntryImage.jobs.last["args"]
      refute payload.key?("storage_path")
    end

    test "create_image records a usage row" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        image = Image.new_with_attributes(
          id: "a", preset_name: "primary", image_urls: [],
          provider: ::Image.providers[:entry_preview], provider_id: 42, feed_id: 7,
          original_url: "http://example.com/a.jpg", final_url: "http://example.com/a-final.jpg",
          storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
          width: 542, height: 304, bytesize: 9_999, placeholder_color: "aabbcc",
          fingerprint: SecureRandom.hex(16)
        )

        record = image.create_image

        assert_equal "42", record.provider_id
        assert_equal 7, record.feed_id
        assert_equal image.storage_path, record.storage_path
        assert_equal 9_999, record.bytesize
        assert_equal "https://s3.amazonaws.com/bucket/a/abc.jpg", record.data["legacy_storage_url"]
        assert_equal "primary", record.data["preset"]
        assert_equal "http://example.com/a-final.jpg", record.data["final_url"]
      end
    end

    test "storage_path and content type follow the preset format" do
      image = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg"
      )
      assert_equal "webp", image.preset.format
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304", "webp"), image.storage_path
      assert_equal "image/webp", image.r2_storage_options["Content-Type"]
    end

    # variant names the rendering recipe, not the result. A 180x180 touch icon
    # rendered by the 200x200 limit recipe stays 180x180 and is still variant
    # "200x200" -- keying on the actual output would fragment the namespace and
    # break dedup between two renditions of the same recipe.
    test "icon presets keep their recipe as the variant and store png" do
      %w[favicon touch_icon].zip(["32x32", "200x200"]).each do |preset_name, variant|
        image = Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: preset_name, image_urls: [],
          provider: ::Image.providers[:feed_icon], provider_id: 1,
          original_url: "http://example.com/favicon.ico",
          width: 17, height: 17
        )
        assert_equal variant, image.variant
        assert_equal "png", image.preset.format
        assert_equal "image/png", image.r2_storage_options["Content-Type"]
        assert_equal :icon_crop, image.preset.crop
      end
    end
  end
end
