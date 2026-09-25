require "test_helper"

module ImageCrawler
  class DedupeTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @original_url = "http://example.com/image.jpg"
      @image = Image.new_with_attributes(
        id: SecureRandom.hex,
        kind: ::Image.kinds[:poster], preset_name: "primary",
        image_urls: [],
        provider: ::Image.providers[:entry_preview],
        provider_id: 2,
        feed_id: 9
      )
    end

    def seed_row(provider_id: 1, data: {"final_url" => "http://example.com/image-final.jpg"})
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
        assert_equal row.original_fingerprint, attached.original_fingerprint
        assert_equal 12_345, attached.bytesize
        assert_equal ::Image.kinds.key(@image.kind), attached.kind, "the attached row carries its own kind, not the shared object's"
        assert_equal "http://example.com/image-final.jpg", attached.final_url

        _, payload = EntryImage.jobs.last["args"]
        assert_equal row.storage_path, payload["storage_path"]
        assert_equal "2", payload["provider_id"]
      end
    end
  end
end
