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
  end
end