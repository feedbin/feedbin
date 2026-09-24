require "test_helper"
module ImageCrawler
  class DownloadCacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def image(preset_name = "primary")
      Image.new_with_attributes(
        id: SecureRandom.hex, kind: ::Image.kinds[:poster], preset_name:,
        image_urls: [], provider: ::Image.providers[:entry_preview], provider_id: 1
      )
    end

    # A candidate that failed is not downloaded again, for any image of the
    # same preset; another preset keeps its own record.
    def test_a_failed_url_is_not_downloaded_again
      url = "http://example.com/image.jpg"
      assert DownloadCache.new(url, image).download?

      DownloadCache.new(url, image).failed!

      refute DownloadCache.new(url, image).download?
      assert DownloadCache.new("http://example.com/other.jpg", image).download?
      assert DownloadCache.new(url, image("twitter")).download?
    end
  end
end
