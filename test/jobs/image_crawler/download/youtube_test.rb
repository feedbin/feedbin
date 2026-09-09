require "test_helper"
module ImageCrawler
  class Download::YoutubeTest < ActiveSupport::TestCase
    def test_should_download_valid_image
      id = SecureRandom.hex

      max_url = "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg"
      sd_url = "https://i.ytimg.com/vi/#{id}/sddefault.jpg"

      stub_request(:get, max_url).to_return(status: 404)
      stub_request(:get, sd_url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")

      download = Download.download!("https://www.youtube.com/watch?v=#{id}", minimum_size: 8)
      assert download.valid?

      assert_instance_of Download::Youtube, download
      assert_requested :get, max_url
      assert_requested :get, sd_url
    end

    # sddefault (640x480) still clears the 542x304 crop validation; hqdefault
    # (480x360) does not, so it only exists as a last resort.
    def test_should_fall_back_through_every_size
      id = SecureRandom.hex

      max_url = "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg"
      sd_url = "https://i.ytimg.com/vi/#{id}/sddefault.jpg"
      hq_url = "https://i.ytimg.com/vi/#{id}/hqdefault.jpg"

      stub_request(:get, max_url).to_return(status: 404)
      stub_request(:get, sd_url).to_return(status: 404)
      stub_request(:get, hq_url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")

      download = Download.download!("https://www.youtube.com/watch?v=#{id}", minimum_size: 8)
      assert download.valid?
      assert_equal hq_url, download.image_url
    end

    # An og:image pointing straight at a thumbnail is how most YouTube
    # previews actually reach us — the publisher picks the size, and it is
    # usually sddefault, which is 4:3 with letterbox bars.
    def test_should_upgrade_a_thumbnail_url_to_maxresdefault
      id = SecureRandom.hex

      max_url = "https://i.ytimg.com/vi/#{id}/maxresdefault.jpg"
      sd_url = "https://i.ytimg.com/vi/#{id}/sddefault.jpg"

      stub_request(:get, max_url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")

      download = Download.download!(sd_url, minimum_size: 8)

      assert_instance_of Download::Youtube, download
      assert download.valid?
      assert_equal max_url, download.image_url
      assert_requested :get, max_url
      refute_requested :get, sd_url
    end

    def test_should_recognize_every_thumbnail_url_shape
      id = SecureRandom.hex

      [
        "https://i.ytimg.com/vi/#{id}/sddefault.jpg",
        "https://i9.ytimg.com/vi/#{id}/hqdefault.jpg",
        "https://img.youtube.com/vi/#{id}/0.jpg",
        "https://i.ytimg.com/vi_webp/#{id}/sddefault.webp"
      ].each do |url|
        assert_equal Download::Youtube, Download.find_download_provider(url), url
        assert_equal id, Download::Youtube.recognize_url?(url), url
      end
    end

    def test_should_not_claim_unrelated_youtube_urls
      refute Download.find_download_provider("https://i.ytimg.com/an_webp/other.webp")
      refute Download.find_download_provider("https://yt3.ggpht.com/avatar.jpg")
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