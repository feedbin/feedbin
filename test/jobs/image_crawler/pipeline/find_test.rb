require "test_helper"
module ImageCrawler
  module Pipeline
    class FindTest < ActiveSupport::TestCase
      def setup
        @feed = Feed.first
        @entry = create_entry(@feed)
        flush_redis
      end

      def test_should_copy_image
        image_url = "https://i.ytimg.com/vi/id/maxresdefault.jpg"
        original_url = "https://www.youtube.com/watch?v=id"

        stub_request_file("image.jpeg", image_url, headers: {content_type: "image/jpeg"})
        stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: 0, provider_id: @entry.id)
        Sidekiq::Testing.inline! do
          Find.perform_async(image.to_h)
        end

        image_two = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: 0, provider_id: @entry.id)
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

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: urls, provider: 0, provider_id: @entry.id, entry_url: page_url)
        Sidekiq::Testing.inline! do
          Find.perform_async(image.to_h)
        end

        assert_requested :get, "http://example.com/image/og_image.jpg"
        assert_requested :get, "http://example.com/image/twitter_image.jpg"

        assert_equal 0, EntryImage.jobs.size
        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: urls, provider: 0, provider_id: @entry.id)
        Find.new.perform(image.to_h)
        assert_equal 1, EntryImage.jobs.size
      end

      def test_should_enqueue_recognized_image
        url = "https://i.ytimg.com/vi/id/maxresdefault.jpg"
        image_url = "http://example.com/image.jpg"

        stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: ("lorem " * 3_500))
        id = SecureRandom.hex

        image = Image.new_with_attributes(id: id, preset_name: "primary", image_urls: [image_url], provider: 0, provider_id: @entry.id, entry_url: "https://www.youtube.com/watch?v=id")

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

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: urls, provider: 0, provider_id: @entry.id)
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

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [image_url], provider: 0, provider_id: @entry.id, camo: true)
        Find.new.perform(image.to_h)

        assert_requested :get, camo_url
      end
    end
  end
end