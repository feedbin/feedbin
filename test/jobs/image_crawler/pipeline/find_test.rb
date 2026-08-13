require "test_helper"
module ImageCrawler
  module Pipeline
    class FindTest < ActiveSupport::TestCase
      def setup
        flush_redis
      end

      def test_should_copy_image
        image_url = "https://i.ytimg.com/vi/id/maxresdefault.jpg"
        original_url = "https://www.youtube.com/watch?v=id"

        stub_request_file("image.jpeg", image_url, headers: {content_type: "image/jpeg"})
        stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: 0, provider_id: 1)
        Sidekiq::Testing.inline! do
          Find.perform_async(image.to_h)
        end

        image_two = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: 0, provider_id: 1)
        Find.new.perform(image_two.to_h)

        assert_equal(image_url, EntryImage.jobs.first["args"][1]["original_url"])
        assert_equal("https:/#{image_two.image_name}jpg", EntryImage.jobs.first["args"][1]["processed_url"])
      end

      def test_should_process_an_image
        image_url = "http://example.com/image.jpg"
        page_url = "http://example.com/article"
        urls = [image_url]

        stub_request_file("html.html", page_url)
        stub_request_file("image.jpeg", image_url, headers: {content_type: "image/jpeg"})

        stub_request(:get, "http://example.com/image/og_image.jpg").to_return(status: 404)
        stub_request(:get, "http://example.com/image/twitter_image.jpg").to_return(status: 404)

        stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: urls, provider: 0, provider_id: 1, entry_url: page_url)
        Sidekiq::Testing.inline! do
          Find.perform_async(image.to_h)
        end

        assert_requested :get, "http://example.com/image/og_image.jpg"
        assert_requested :get, "http://example.com/image/twitter_image.jpg"

        assert_equal 0, EntryImage.jobs.size
        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: urls, provider: 0, provider_id: 1)
        Find.new.perform(image.to_h)
        assert_equal 1, EntryImage.jobs.size
      end

      def test_should_enqueue_recognized_image
        url = "https://i.ytimg.com/vi/id/maxresdefault.jpg"
        image_url = "http://example.com/image.jpg"

        stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: ("lorem " * 3_500))
        id = SecureRandom.hex

        image = Image.new_with_attributes(id: id, preset_name: "primary", image_urls: [image_url], provider: 0, provider_id: 1, entry_url: "https://www.youtube.com/watch?v=id")

        assert_difference -> { Process.jobs.size }, +1 do
          Find.new.perform(image.to_h)
        end

        image = Image.new(Process.jobs.first["args"][0])

        assert image.download_path
        assert_equal "https://www.youtube.com/watch?v=id", image.entry_url
        assert_equal "https://i.ytimg.com/vi/id/maxresdefault.jpg", image.final_url
        assert_equal id, image.id
        assert_equal ["http://example.com/image.jpg"], image.image_urls
        assert_equal "https://www.youtube.com/watch?v=id", image.original_url
        assert_equal "primary", image.preset_name

        assert_requested :get, url
        refute_requested :get, image_url
      end

      def test_should_try_all_urls
        urls = [
          "http://example.com/image_1.jpg",
          "http://example.com/image_2.jpg",
          "http://example.com/image_3.jpg"
        ]

        urls.each do |url|
          stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: ("lorem " * 3_500))
        end

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: urls, provider: 0, provider_id: 1)
        Sidekiq::Testing.inline! do
          Find.perform_async(image.to_h)
        end

        assert_requested :get, urls[0]
        assert_requested :get, urls[1]
        assert_requested :get, urls[2]
      end

      def test_should_use_camo
        image_url = "http://example.com/image.jpg"
        camo_url = RemoteFile.camo_url(image_url)

        stub_request_file("image.jpeg", camo_url, headers: {content_type: "image/jpeg"})

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [image_url], provider: 0, provider_id: 1, camo: true)
        Find.new.perform(image.to_h)

        assert_requested :get, camo_url
      end

      def test_should_attach_existing_unified_image_without_downloading
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/image.jpg"
          ::Image.create!(
            provider: :entry_preview,
            provider_id: "1",
            feed_id: 9,
            url: original_url,
            variant: "542x304",
            image_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.storage_path_for(original_url, "542x304"),
            width: 542, height: 304, bytesize: 12_345,
            placeholder_color: "aabbcc",
            data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg"}
          )

          # No storage stubs: a dedupe hit issues no storage API requests.
          image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9)
          Find.new.perform(image.to_h)

          assert_equal 1, EntryImage.jobs.size
          refute_requested :get, original_url
          assert_equal 2, ::Image.entry_images.where(url_fingerprint: ::Image.url_fingerprint_for(original_url, "542x304")).count
        end
      end

      def test_should_download_unified_image_on_dedupe_miss
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/image.jpg"
          stub_request_file("image.jpeg", original_url, headers: {content_type: "image/jpeg"})

          image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9)

          assert_difference -> { Process.jobs.size }, +1 do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
        end
      end

      def test_should_skip_page_fetched_meta_candidate_already_used_in_feed
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          page_url = "http://example.com/article"
          og_url = "http://example.com/og.jpg"
          fresh_url = "http://example.com/inline.jpg"

          stub_request(:get, page_url).to_return(
            status: 200,
            body: %(<html><head><meta property="og:image" content="/og.jpg"></head></html>),
            headers: {content_type: "text/html"}
          )
          stub_request_file("image.jpeg", fresh_url, headers: {content_type: "image/jpeg"})

          ::Image.create!(
            provider: :entry_preview, provider_id: "1", feed_id: 9,
            url: og_url, variant: "542x304", image_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.storage_path_for(og_url, "542x304"),
            width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc",
            data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg"}
          )

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "primary",
            image_urls: [fresh_url],
            provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9,
            entry_url: page_url, page_url: page_url
          )
          Find.new.perform(image.to_h)

          refute_requested :get, og_url
          assert_requested :get, fresh_url
          assert_equal 1, Process.jobs.size
        end
      end

      def test_should_skip_reused_meta_candidate_and_try_the_next_url
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          reused_url = "http://example.com/og.jpg"
          fresh_url = "http://example.com/inline.jpg"

          ::Image.create!(
            provider: :entry_preview, provider_id: "1", feed_id: 9,
            url: reused_url, variant: "542x304", image_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.storage_path_for(reused_url, "542x304"),
            width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc",
            data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg"}
          )
          stub_request_file("image.jpeg", fresh_url, headers: {content_type: "image/jpeg"})

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "primary",
            image_urls: [reused_url, fresh_url],
            provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9,
            page_url: "http://example.com/article", meta_image_urls: [reused_url]
          )
          Find.new.perform(image.to_h)

          refute_requested :get, reused_url
          assert_requested :get, fresh_url
          assert_equal 1, Process.jobs.size
        end
      end

      def test_should_fingerprint_the_original_bytes
        original_url = "http://example.com/image.jpg"
        stub_request_file("image.jpeg", original_url, headers: {content_type: "image/jpeg"})

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9)
        Find.new.perform(image.to_h)

        queued = Image.new(Process.jobs.last["args"][0])
        assert_equal Digest::MD5.file(support_file("image.jpeg")).hexdigest, queued.original_fingerprint
      end

      # Dedupe's shortcut is skip-the-download-because-a-row-exists. For icons
      # the row proves nothing about the bytes behind the URL, so the fetch
      # always happens and the short circuit is after it.
      def test_should_always_download_an_icon_even_with_a_row_for_the_url
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/favicon.ico"
          stub_request_file("favicon.ico", original_url, headers: {content_type: "image/x-icon"})

          ::Image.create!(
            provider: :feed_icon, provider_id: "5", feed_id: 9,
            url: original_url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("different bytes"),
            storage_path: ::Image.content_storage_path_for(Digest::MD5.hexdigest("different bytes"), "32x32", "png"),
            width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc"
          )

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [original_url],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9
          )

          assert_difference -> { Process.jobs.size }, +1 do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
        end
      end

      # An unchanged icon must cost one download and nothing else: no vips
      # work, no upload, and no row write -- the row's updated_at is a view
      # cache key, so a write here would invalidate every view referencing it
      # on every crawl.
      def test_should_stop_after_the_download_when_the_icon_is_unchanged
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/favicon.ico"
          stub_request_file("favicon.ico", original_url, headers: {content_type: "image/x-icon"})
          fingerprint = Digest::MD5.file(support_file("favicon.ico")).hexdigest

          row = ::Image.create!(
            provider: :feed_icon, provider_id: "5", feed_id: 9,
            url: original_url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: fingerprint,
            storage_path: ::Image.content_storage_path_for(fingerprint, "32x32", "png"),
            width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc",
            updated_at: 1.year.ago
          )
          # Captured once, not recomputed after the call: two independent
          # `1.year.ago` evaluations can straddle a second boundary and make
          # this assertion flaky even when the row was never touched.
          expected_updated_at = row.updated_at

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [original_url],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9
          )

          assert_no_difference -> { Process.jobs.size } do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
          assert_equal expected_updated_at.to_f, row.reload.updated_at.to_f
        end
      end
    end
  end
end