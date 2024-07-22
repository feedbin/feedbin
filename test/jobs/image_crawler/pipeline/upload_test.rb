require "test_helper"
module ImageCrawler
  module Pipeline
    class UploadTest < ActiveSupport::TestCase
      def setup
        flush_redis
      end

      def test_should_upload
        cache_key = "cache_key"
        id = SecureRandom.hex
        download_path = copy_support_file("image.jpeg")
        processed_path = download_path
        original_url = "http://example.com/image.jpg"
        final_url = original_url
        placeholder_color = "0867e2"
        width = 300
        height = 200


        image = Image.new_with_attributes(id:, preset_name: "primary", image_urls: [], provider: 0, provider_id: 1, fingerprint: SecureRandom.hex, download_path:, original_url:, final_url:, processed_path:, width:, height:, placeholder_color:)

        stub_request(:put, /s3\.amazonaws\.com/)

        assert_difference -> { EntryImage.jobs.size }, +1 do
          Upload.new.perform(image.to_h)
        end

        saved_id, options = EntryImage.jobs.last.safe_dig("args")

        download_cache = DownloadCache.new(original_url, image)
        assert_equal(id, saved_id)

        assert_equal(original_url,      download_cache.cached_image.final_url)
        assert_equal("https:",          download_cache.cached_image.storage_url)
        assert_equal(placeholder_color, download_cache.cached_image.placeholder_color)

        assert_equal(original_url, options["original_url"])
        assert_equal("https:",     options["processed_url"])
        assert_equal(width,        options["width"])
        assert_equal(height,       options["height"])
      end
    end
  end
end