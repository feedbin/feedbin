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

      def test_should_produce_webp_for_unified_presets
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          download_path = copy_support_file("image.jpeg")
          image = Image.new_with_attributes(
            id: SecureRandom.hex,
            preset_name: "primary",
            image_urls: [],
            provider: ::Image.providers[:entry_preview],
            provider_id: 1,
            feed_id: 1,
            original_url: "http://example.com/image.jpg",
            final_url: "http://example.com/image.jpg",
            download_path: download_path,
            original_extension: "jpeg"
          )

          assert_difference -> { Upload.jobs.size }, +1 do
            Process.new.perform(image.to_h)
          end

          queued = Image.new(Upload.jobs.last["args"].first)
          assert queued.webp_path.present?
          assert_equal :webp, ImageFormat.detect(queued.webp_path)
          assert_equal File.size(queued.webp_path), queued.bytesize
          assert_equal Digest::MD5.file(queued.webp_path).hexdigest, queued.fingerprint
          assert_equal "jpg", queued.processed_extension
          assert_equal 542, queued.width
          assert_equal 304, queued.height

          File.unlink(queued.processed_path)
          File.unlink(queued.webp_path)
        end
      end

      def test_should_not_produce_webp_without_r2_configuration
        download_path = copy_support_file("image.jpeg")
        image = Image.new_with_attributes(
          id: SecureRandom.hex,
          preset_name: "primary",
          image_urls: [],
          provider: ::Image.providers[:entry_preview],
          provider_id: 1,
          original_url: "http://example.com/image.jpg",
          download_path: download_path,
          original_extension: "jpeg"
        )

        Process.new.perform(image.to_h)

        queued = Image.new(Upload.jobs.last["args"].first)
        assert_nil queued.webp_path
        File.unlink(queued.processed_path)
      end
    end
  end
end
