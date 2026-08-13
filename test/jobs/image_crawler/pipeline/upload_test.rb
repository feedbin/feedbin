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

      def test_should_dual_write_unified_images
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          id = SecureRandom.hex
          download_path = copy_support_file("image.jpeg")
          webp_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/image.jpg"

          image = Image.new_with_attributes(
            id: id, preset_name: "primary", image_urls: [],
            provider: ::Image.providers[:entry_preview], provider_id: 1, feed_id: 1,
            fingerprint: SecureRandom.hex(16),
            original_url: original_url, final_url: original_url,
            download_path: download_path, processed_path: download_path,
            webp_path: webp_path, bytesize: File.size(webp_path),
            width: 542, height: 304, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          r2_put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .with(headers: {"Content-Type" => "image/webp"})
          # ensure_stored HEADs the object it just wrote; not the behavior under
          # test here, so it stays a plain 200.
          stub_request(:head, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 200)

          assert_difference -> { ::Image.count }, +1 do
            assert_difference -> { EntryImage.jobs.size }, +1 do
              Upload.new.perform(image.to_h)
            end
          end

          assert_requested r2_put

          record = ::Image.entry_images.find_by(url_fingerprint: ::Image.url_fingerprint_for(original_url, "542x304"))
          assert_equal "1", record.provider_id
          assert_equal image.storage_path, record.storage_path
          assert record.data["legacy_storage_url"].present?

          _, payload = EntryImage.jobs.last["args"]
          assert_equal image.storage_path, payload["storage_path"]

          # the positive redis cache is retired for unified images
          assert_nil DownloadCache.new(original_url, image).cached_image
        end
      end

      def test_should_degrade_to_legacy_when_r2_upload_fails
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          id = SecureRandom.hex
          download_path = copy_support_file("image.jpeg")
          webp_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/image.jpg"

          image = Image.new_with_attributes(
            id: id, preset_name: "primary", image_urls: [],
            provider: ::Image.providers[:entry_preview], provider_id: 1, feed_id: 1,
            fingerprint: SecureRandom.hex(16),
            original_url: original_url, final_url: original_url,
            download_path: download_path, processed_path: download_path,
            webp_path: webp_path, bytesize: File.size(webp_path),
            width: 542, height: 304, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 500)

          assert_no_difference -> { ::Image.count } do
            assert_difference -> { EntryImage.jobs.size }, +1 do
              Upload.new.perform(image.to_h)
            end
          end

          _, payload = EntryImage.jobs.last["args"]
          refute payload.key?("storage_path")

          assert DownloadCache.new(original_url, image).cached_image.present?
        end
      end

      def test_should_store_icons_only_in_r2
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.png")
          original_url = "http://example.com/favicon.ico"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("bytes"),
            original_url: original_url, final_url: original_url,
            download_path: processed_path, processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 32, height: 32, placeholder_color: "0867e2"
          )

          legacy = stub_request(:put, /s3\.amazonaws\.com/)
          r2_put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .with(headers: {"Content-Type" => "image/png"})
          # ensure_stored HEADs the object it just wrote; not the behavior under
          # test here, so it stays a plain 200.
          stub_request(:head, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 200)

          assert_difference -> { ::Image.count }, +1 do
            Upload.new.perform(image.to_h)
          end

          assert_requested r2_put
          assert_not_requested legacy

          record = ::Image.find_by(provider: ::Image.providers[:feed_icon], provider_id: "5")
          assert_equal image.storage_path, record.storage_path
          assert_equal Digest::MD5.hexdigest("bytes"), record.original_fingerprint.delete("-")
        end
      end

      # The R2 PUT lands before create_image takes the storage lock, so a sweep
      # in between deletes an object nothing references yet. Once the row
      # exists no sweep can touch it, so one HEAD after attaching closes the
      # window -- and re-uploading is the only recovery, because unchanged?
      # would short-circuit every later crawl before it reprocessed.
      #
      # Preset is touch_icon, not podcast: Task 3 of this plan is what flips
      # podcast/podcast_feed to unified+content_addressed, and this task runs
      # before it, so podcast doesn't take this code path yet. touch_icon
      # already carries both flags today and matches the 200x200 geometry
      # already used below, so it exercises the same mechanism this task adds.
      def test_should_re_upload_when_the_object_vanished_before_the_row_existed
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/cover.jpg"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "touch_icon", image_urls: [],
            provider: ::Image.providers[:entry_icon], provider_id: 5, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("bytes"),
            original_url: original_url, final_url: original_url,
            download_path: processed_path, processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 200, height: 200, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
          head = stub_request(:head, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 404)

          Upload.new.perform(image.to_h)

          assert_requested head
          assert_requested put, times: 2
        end
      end

      # Same substitution as above, and for the same reason: podcast isn't
      # unified/content_addressed until Task 3.
      def test_should_not_re_upload_when_the_object_is_still_there
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/cover.jpg"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "touch_icon", image_urls: [],
            provider: ::Image.providers[:entry_icon], provider_id: 6, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("other bytes"),
            original_url: original_url, final_url: original_url,
            download_path: processed_path, processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 200, height: 200, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
          stub_request(:head, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 200)

          Upload.new.perform(image.to_h)

          assert_requested put, times: 1
        end
      end
    end
  end
end