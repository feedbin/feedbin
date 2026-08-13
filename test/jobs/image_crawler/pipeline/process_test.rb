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

      def test_should_reject_repeated_fingerprint_in_feed
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          # Compute the fingerprint this exact source produces.
          reference = Processor::Cropper.new(copy_support_file("image.jpeg"), crop: :smart_crop, extension: "jpeg", width: 542, height: 304).crop_pair!
          fingerprint = reference[:webp].fingerprint
          File.unlink(reference[:jpg].file)
          File.unlink(reference[:webp].file)

          original_url = "http://example.com/cache-busted.jpg?v=2"
          ::Image.create!(
            provider: :entry_preview, provider_id: "1", feed_id: 9,
            url: "http://example.com/cache-busted.jpg?v=1",
            variant: "542x304",
            image_fingerprint: fingerprint,
            storage_path: ::Image.storage_path_for("http://example.com/cache-busted.jpg?v=1", "542x304"),
            width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc"
          )

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "primary",
            image_urls: ["http://example.com/next-candidate.jpg"],
            provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9,
            page_url: "http://example.com/article", meta_image_urls: [original_url],
            original_url: original_url, final_url: original_url,
            download_path: copy_support_file("image.jpeg"), original_extension: "jpeg"
          )

          assert_no_difference -> { Upload.jobs.size } do
            assert_difference -> { FindCritical.jobs.size }, +1 do
              Process.new.perform(image.to_h)
            end
          end

          requeued = Image.new(FindCritical.jobs.last["args"].first)
          assert_equal ["http://example.com/next-candidate.jpg"], requeued.image_urls
          assert_equal 9, requeued.feed_id
        end
      end

      # Regression test for the crop! vs. crop_pair! branch: content-addressed
      # presets are unified but must not take the dual-format path -- geometry
      # returns a saved Processed (icon_crop), not an unsaved pipeline, and
      # crop_pair! calling .convert on it raises NoMethodError.
      def test_should_produce_a_single_png_for_content_addressed_presets
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          download_path = copy_support_file("favicon.ico")
          image = Image.new_with_attributes(
            id: SecureRandom.hex,
            preset_name: "favicon",
            image_urls: [],
            provider: ::Image.providers[:feed_icon],
            provider_id: 5,
            feed_id: 9,
            original_url: "http://example.com/favicon.ico",
            final_url: "http://example.com/favicon.ico",
            download_path: download_path,
            original_extension: "unknown"
          )

          assert_difference -> { Upload.jobs.size }, +1 do
            Process.new.perform(image.to_h)
          end

          queued = Image.new(Upload.jobs.last["args"].first)
          assert_nil queued.webp_path
          assert_equal "png", queued.processed_extension
          assert_equal File.size(queued.processed_path), queued.bytesize
          assert_equal Digest::MD5.file(queued.processed_path).hexdigest, queued.fingerprint
          assert_equal 32, queued.width
          assert_equal 32, queued.height

          File.unlink(queued.processed_path)
        end
      end
    end
  end
end
