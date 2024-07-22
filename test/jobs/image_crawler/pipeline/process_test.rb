require "test_helper"
module ImageCrawler
  module Pipeline
    class ProcessTest < ActiveSupport::TestCase
      def setup
        flush_redis
      end

      def test_should_enqueue_upload
        id = SecureRandom.hex
        path = copy_support_file("image.jpeg")
        url = "http://example.com/image.jpg"
        cache_key = "cache_key"

        image = Image.new_with_attributes(id: id, preset_name: "primary", provider: 0, provider_id: 1, download_path: path, original_url: url, final_url: url, image_urls: [])

        assert_difference -> { Upload.jobs.size }, +1 do
          Process.new.perform(image.to_h)
        end

        image = Image.new(Upload.jobs.first["args"].first)

        assert_equal(id, image.id)
        assert_equal("primary", image.preset_name)
        assert(image.processed_path.end_with?(".jpg"), "Should contain path to image")
        assert_equal(url, image.original_url)
        assert_equal(url, image.final_url)
        assert_equal(6, image.placeholder_color.length)
      end

      def test_should_enqueue_find
        id = SecureRandom.hex
        path = Tempfile.new.path
        url = "http://example.com/image.jpg"
        all_urls = ["http://example.com/image_2.jpg", "http://example.com/image_3.jpg"]

        image = Image.new_with_attributes(id: id, preset_name: "primary", provider: 0, provider_id: 1, download_path: path, original_url: url, final_url: url, image_urls: all_urls)

        assert_difference -> { FindCritical.jobs.size }, +1 do
          Process.new.perform(image.to_h)
        end

        image = Image.new(FindCritical.jobs.first["args"].first)

        assert_equal(id, image.id)
        assert_equal("primary", image.preset_name)
        assert_equal(all_urls, image.image_urls)
      end
    end
  end
end
