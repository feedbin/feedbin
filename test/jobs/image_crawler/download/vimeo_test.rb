require "test_helper"
module ImageCrawler
  class Download::VimeoTest < ActiveSupport::TestCase
    def test_should_download_valid_image
      url = "http://example.com/image.jpg"
      stub_request(:get, /vimeo\.com\/api/).to_return(body: {thumbnail_url: url}.to_json)

      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")
      download = Download.download!("https://player.vimeo.com/video/CMGfYFaJoF7/", minimum_size: 8)
      assert download.valid?
      assert_instance_of Download::Vimeo, download
    end

    # Download.download! dispatches on the original url passed in
    # (http://vimeo.com/favicon.ico matches Vimeo's own supported_urls
    # pattern), but #download then fetches a *derived* oEmbed thumbnail url --
    # a different resource than the one @etag was computed for. Sending the
    # validator there would risk a false 304 for bytes never actually
    # validated against this URL.
    def test_should_not_send_conditional_headers_to_the_derived_thumbnail_url
      url = "http://example.com/image.jpg"
      stub_request(:get, /vimeo\.com\/api/).to_return(body: {thumbnail_url: url}.to_json)

      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")

      download = Download.download!("http://vimeo.com/favicon.ico", minimum_size: 8, etag: "\"abc123\"")

      assert_instance_of Download::Vimeo, download
      assert download.valid?
      assert_requested :get, url do |req|
        !req.headers.key?("If-None-Match")
      end
    end
  end
end