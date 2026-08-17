require "test_helper"

module ImageCrawler
  class DedupeTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @original_url = "http://example.com/image.jpg"
      @image = Image.new_with_attributes(
        id: SecureRandom.hex,
        preset_name: "primary",
        image_urls: [],
        provider: ::Image.providers[:entry_preview],
        provider_id: 2,
        feed_id: 9
      )
    end

    def seed_row(provider_id: 1, data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg", "final_url" => "http://example.com/image-final.jpg"})
      create_image_row(provider_id: provider_id, url: @original_url, data: data)
    end

    test "returns false when nothing is stored for the url" do
      with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
        refute Dedupe.attach(@original_url, @image)
      end
    end

    test "attaches to an existing image with no storage API calls" do
      with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
        row = seed_row

        # No webmock stubs: any HTTP request here would raise. Attaching is
        # purely a database operation — the rows share both stored objects.
        assert_difference -> { ::Image.count }, +1 do
          assert Dedupe.attach(@original_url, @image)
        end

        attached = ::Image.entry_images.find_by(provider_id: "2")
        assert_equal row.storage_path, attached.storage_path
        assert_equal row.image_fingerprint, attached.image_fingerprint
        assert_equal 12_345, attached.bytesize
        assert_equal row.data["legacy_storage_url"], attached.data["legacy_storage_url"]

        _, payload = EntryImage.jobs.last["args"]
        assert_equal row.storage_path, payload["storage_path"]
        assert_equal "2", payload["provider_id"]
        assert_equal "http://example.com/image-final.jpg", payload["original_url"]
        assert_equal row.data["legacy_storage_url"], payload["processed_url"]
      end
    end
  end
end
