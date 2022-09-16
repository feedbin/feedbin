require "test_helper"
module Crawler
  module Image
    class Download::YoutubeTest < ActiveSupport::TestCase
      def test_should_download_valid_image
        id = SecureRandom.hex

        max_url = "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg"
        hq_url = "https://i.ytimg.com/vi/#{id}/hqdefault.jpg"

        stub_request(:get, max_url).to_return(status: 404)
        stub_request(:get, hq_url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")

        download = Download.download!("https://www.youtube.com/watch?v=#{id}", minimum_size: 8)
        assert download.valid?

        assert_instance_of Download::Youtube, download
        assert_requested :get, max_url
        assert_requested :get, hq_url
      end

      def test_should_stop_at_first_image
        id = SecureRandom.hex

        max_url = "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg"
        hq_url = "https://i.ytimg.com/vi/#{id}/hqdefault.jpg"

        stub_request(:get, max_url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")
        stub_request(:get, hq_url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")

        download = Download.download!("https://www.youtube.com/watch?v=#{id}", minimum_size: 8)
        assert download.valid?

        assert_instance_of Download::Youtube, download
        assert_requested :get, max_url
        refute_requested :get, hq_url
      end
    end
  end
end