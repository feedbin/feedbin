require "test_helper"

module IconCrawler
  module Provider
    class FaviconTest < ActiveSupport::TestCase
      setup do
        flush_redis
        @feed = Feed.first
      end

      test "should get favicon from icon link" do
        @feed = Feed.first

        body = <<-eot
        <html>
            <head>
                <link rel="icon" href="icon">
                <link rel="Shortcut Icon" href="shortcut-icon">
                <link rel="apple-touch-icon" href="apple-touch-icon">
                <link rel="apple-touch-icon-precomposed" href="apple-touch-icon-precomposed">
            </head>
        </html>
        eot

        stub_request(:get, @feed.site_url)
          .to_return(body: body, status: 200)

        Favicon.new.perform(@feed.host)

        image = ImageCrawler::Image.new(ImageCrawler::Pipeline::Find.jobs.first["args"].first)
        assert_equal(@feed.host, image.icon_provider_id)
        assert_equal(2, image.icon_provider)
        assert_equal(["http://kottke.org/icon", "http://kottke.org/shortcut-icon", "http://kottke.org/favicon.ico"], image.image_urls)

        image = ImageCrawler::Image.new(ImageCrawler::Pipeline::Find.jobs.last["args"].first)
        assert_equal(@feed.host, image.icon_provider_id)
        assert_equal(3, image.icon_provider)
        assert_equal(["http://kottke.org/apple-touch-icon", "http://kottke.org/apple-touch-icon-precomposed"], image.image_urls)
      end

      test "should skip update if recently checked" do
        Icon.provider_favicon.create!(provider_id: @feed.host, url: "url")
        result = Favicon.new.perform(@feed.host)
        assert_nil(result)
        assert_nil(ImageCrawler::Pipeline::Find.jobs.first)
      end

      test "should create icon records" do

        body = <<-eot
        <html>
            <head>
                <link rel="apple-touch-icon" href="apple-touch-icon">
            </head>
        </html>
        eot

        stub_request(:get, @feed.site_url)
          .to_return(status: 200, body: body)

        favicon_url = Addressable::URI.join(@feed.site_url, "/favicon.ico").to_s
        stub_request_file("favicon.ico", favicon_url)

        touch_icon_url = Addressable::URI.join(@feed.site_url, "/apple-touch-icon").to_s
        stub_request_file("favicon.ico", touch_icon_url)

        stub_request(:put, /s3\.amazonaws\.com/)
          .to_return(status: 200)

        assert_difference -> {Icon.count}, +2 do
          assert_difference -> {RemoteFile.count}, +2 do
            Sidekiq::Testing.inline! do
              Favicon.perform_async(@feed.host)
            end
          end
        end

        assert_not_nil(RemoteFile.find_by(original_url: touch_icon_url))
        assert_not_nil(RemoteFile.find_by(original_url: favicon_url))

        assert_equal(favicon_url, Icon.provider_favicon.find_by_provider_id(@feed.host).url)
        assert_equal(touch_icon_url, Icon.provider_touch_icon.find_by_provider_id(@feed.host).url)
      end
    end
  end
end