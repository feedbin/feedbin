require "test_helper"

module IconCrawler
  class BuildTest < ActiveSupport::TestCase
    setup do
      @page_url = URI.parse("http://example.com")
      @icon_url = @page_url.dup
      @icon_url.path = "/icons/favicon.ico"
      @default_url = @page_url.dup
      @default_url.path = "/favicon.ico"
    end

    test "should get favicon from icon link" do
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

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request_file("favicon.ico", @icon_url)

      Build.new.perform(@page_url.host)

      image = ImageCrawler::Image.new(ImageCrawler::Pipeline::Find.jobs.first["args"].first)
      assert_equal(@page_url.host, image.icon_provider_id)
      assert_equal(2, image.icon_provider)
      assert_equal(["http://example.com/icon", "http://example.com/shortcut-icon", "http://example.com/favicon.ico"], image.image_urls)

      image = ImageCrawler::Image.new(ImageCrawler::Pipeline::Find.jobs.last["args"].first)
      assert_equal(@page_url.host, image.icon_provider_id)
      assert_equal(3, image.icon_provider)
      assert_equal(["http://example.com/apple-touch-icon", "http://example.com/apple-touch-icon-precomposed"], image.image_urls)
    end
  end
end