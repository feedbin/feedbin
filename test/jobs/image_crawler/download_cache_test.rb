require "test_helper"
module ImageCrawler
  class DownloadCacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_save_url
      image_url = "http://example.com/example/example.jpg"
      storage_url = "http://s3.com/example/example.jpg"
      public_id = SecureRandom.hex

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      cache.save(storage_url: storage_url, image_url: image_url)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      assert_equal(storage_url, cache.storage_url)
    end

    def test_should_copy_existing_image
      image_url = "http://example.com/example/example.jpg"
      storage_url = "http://s3.com/example/example.jpg"
      public_id = SecureRandom.hex

      stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      refute cache.copied?

      cache.save(storage_url: storage_url, image_url: image_url)
      cache.copy

      assert cache.copied?
      assert cache.storage_url.include?(public_id)
    end

    def test_should_fail_to_copy_missing_image
      image_url = "http://example.com/example/example.jpg"
      storage_url = "http://s3.com/example/example.jpg"
      public_id = SecureRandom.hex
      s3_host = /s3\.amazonaws\.com/

      stub_request(:put, s3_host).to_return(status: 404)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      cache.save(storage_url: storage_url, image_url: image_url)
      cache.copy
      refute cache.copied?
      assert_requested :put, s3_host
    end
  end
end