require "test_helper"
module ImageCrawler
  module Pipeline
    class UploadTest < ActiveSupport::TestCase
      def setup
        flush_redis
      end

      def store_url(image)
        "https://test-account.storage.example.com/images-test/#{image.storage_path}"
      end

      def test_should_store_the_object_write_the_row_and_call_back
        with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/image.jpg"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, kind: ::Image.kinds[:poster], preset_name: "primary", image_urls: [],
            provider: ::Image.providers[:entry_preview], provider_id: 1, feed_id: 1,
            fingerprint: SecureRandom.hex(16), original_fingerprint: SecureRandom.hex(16),
            original_url: original_url, final_url: original_url,
            processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 542, height: 304, placeholder_color: "0867e2"
          )

          put = stub_request(:put, store_url(image)).with(headers: {"Content-Type" => "image/jpeg"})

          assert_difference -> { ::Image.count }, +1 do
            assert_difference -> { EntryImage.jobs.size }, +1 do
              Upload.new.perform(image.to_h)
            end
          end

          assert_requested put
          refute File.exist?(processed_path), "the processed file is removed"

          record = ::Image.entry_images.find_by(url_fingerprint: ::Image.url_fingerprint_for(original_url, "542x304"))
          assert_equal "1", record.provider_id
          assert_equal image.storage_path, record.storage_path

          id, payload = EntryImage.jobs.last["args"]
          assert_equal image.id, id
          assert_equal image.storage_path, payload["storage_path"]
        end
      end

      # A callback for a failed write would hand the receiver a row nobody
      # wrote.
      def test_should_not_write_a_row_or_call_back_when_the_store_fails
        with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/image.jpg"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, kind: ::Image.kinds[:poster], preset_name: "primary", image_urls: [],
            provider: ::Image.providers[:entry_preview], provider_id: 1, feed_id: 1,
            fingerprint: SecureRandom.hex(16), original_fingerprint: SecureRandom.hex(16),
            original_url: original_url, final_url: original_url,
            processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 542, height: 304, placeholder_color: "0867e2"
          )

          stub_request(:put, store_url(image)).to_return(status: 500)

          assert_no_difference -> { ::Image.count } do
            assert_no_difference -> { EntryImage.jobs.size } do
              Upload.new.perform(image.to_h)
            end
          end
          refute File.exist?(processed_path), "the processed file is removed"
        end
      end

      def test_should_store_icons_as_png
        with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.png")

          image = Image.new_with_attributes(
            id: SecureRandom.hex, kind: ::Image.kinds[:site_icon], preset_name: "favicon", image_urls: [],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("bytes"),
            original_url: "http://example.com/favicon.ico", final_url: "http://example.com/favicon.ico",
            processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 32, height: 32, placeholder_color: "0867e2"
          )

          put = stub_request(:put, store_url(image)).with(headers: {"Content-Type" => "image/png"})

          assert_difference -> { ::Image.count }, +1 do
            Upload.new.perform(image.to_h)
          end

          assert_requested put
          record = ::Image.find_by(provider: ::Image.providers[:feed_icon], provider_id: "5")
          assert_equal image.storage_path, record.storage_path
          assert_equal Digest::MD5.hexdigest("bytes"), record.original_fingerprint.delete("-")
        end
      end

      # Episode art has no callback: the row is all a reader needs.
      def test_should_store_episode_art_without_a_callback
        with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")

          image = Image.new_with_attributes(
            id: SecureRandom.hex, kind: ::Image.kinds[:cover_art], preset_name: "podcast", image_urls: [],
            provider: ::Image.providers[:entry_icon], provider_id: 11, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("cover bytes"),
            original_url: "http://example.com/cover.jpg", final_url: "http://example.com/cover.jpg",
            processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 200, height: 200, placeholder_color: "0867e2"
          )

          put = stub_request(:put, store_url(image)).with(headers: {"Content-Type" => "image/jpeg"})

          assert_difference -> { ::Image.count }, +1 do
            assert_no_difference -> { Sidekiq::Worker.jobs.size } do
              Upload.new.perform(image.to_h)
            end
          end

          assert_requested put
          assert image.storage_path.end_with?(".jpg")
        end
      end

      def test_should_call_back_for_show_art
        with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")

          image = Image.new_with_attributes(
            id: SecureRandom.hex, kind: ::Image.kinds[:cover_art], preset_name: "podcast_feed", image_urls: [],
            provider: ::Image.providers[:feed_icon], provider_id: 21, feed_id: 21,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("show bytes"),
            original_url: "http://example.com/show.jpg", final_url: "http://example.com/show.jpg",
            processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 200, height: 200, placeholder_color: "0867e2"
          )

          put = stub_request(:put, store_url(image)).with(headers: {"Content-Type" => "image/jpeg"})

          assert_difference -> { ItunesFeedImage.jobs.size }, +1 do
            Upload.new.perform(image.to_h)
          end

          assert_requested put
          _, payload = ItunesFeedImage.jobs.last["args"]
          assert_equal image.storage_path, payload["storage_path"]
          assert_equal "21", payload["provider_id"]
        end
      end
    end
  end
end
