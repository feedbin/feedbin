require "test_helper"
module Crawler
  module Image

    class Download::InstagramTest < ActiveSupport::TestCase
      def test_should_download_valid_image
        url = "http://example.com/image.jpg"
        stub_request(:get, /graph\.facebook\.com/).to_return(body: {thumbnail_url: url}.to_json)

        stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")
        download = Download.download!("https://www.instagram.com/p/CMGfYFaJoF7/", minimum_size: 8)
        assert download.valid?
        assert_instance_of Download::Instagram, download
      end
    end
  end
end