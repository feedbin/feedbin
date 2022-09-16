require "test_helper"
module ImageCrawler
  class MetaImagesTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_find_urls
      url = "http://example.com/"
      stub_request_file("html.html", url)
      urls = MetaImages.find_urls(url)
      assert urls.length == 2
      assert urls.map(&:to_s).include?("http://example.com/image/og_image.jpg")
      assert urls.map(&:to_s).include?("http://example.com/image/twitter_image.jpg")
    end

    def test_should_not_download_file
      url = "http://example.com/"
      stub_request(:get, url).to_return(status: 404)
      urls = MetaImages.find_urls(url)
      assert urls.empty?
    end

    def test_should_be_invalid_url
      url = "http://invalid\\.com"
      assert_raises(Addressable::URI::InvalidURIError) do
        MetaImages.new(url).find_urls
      end
    end

    def test_should_be_invalid_no_host
      url = "invalid"
      assert_raises(Addressable::URI::InvalidURIError) do
        MetaImages.new(url).find_urls
      end
    end

    def test_should_determine_download_status
      url = "http://example.com/"
      stub_request_file("html.html", url)
      urls = MetaImages.new(url)
      assert urls.needs_download?
      urls.find_urls

      urls = MetaImages.new(url)
      assert !urls.needs_download?
    end

    def test_should_not_download_from_site_with_no_meta
      url = Addressable::URI.parse("http://example.com/article")
      cache = MetaImagesCache.new(url)
      cache.has_meta!(false)

      urls = MetaImages.new(url)
      assert !urls.needs_download?
    end
  end
end