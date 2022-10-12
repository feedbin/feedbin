require "test_helper"
module ImageCrawler
  class DownloadCacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_save_data
      image_url = "http://example.com/example/example.jpg"
      storage_url = "http://s3.com/example/example.jpg"
      public_id = SecureRandom.hex
      placeholder_color = SecureRandom.hex.first(6)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      cache.save(storage_url:, image_url:, placeholder_color:)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      assert_equal(storage_url, cache.storage_url)
      assert_equal(image_url, cache.image_url)
      assert_equal(placeholder_color, cache.placeholder_color)
    end

    def test_should_copy_existing_image
      image_url = "http://example.com/example/example.jpg"
      storage_url = "http://s3.com/example/example.jpg"
      public_id = SecureRandom.hex
      placeholder_color = SecureRandom.hex.first(6)

      stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      refute cache.copied?

      cache.save(storage_url:, image_url:, placeholder_color:)
      cache.copy

      assert cache.copied?
      assert cache.storage_url.include?(public_id)
    end

    def test_should_fail_to_copy_missing_image
      image_url = "http://example.com/example/example.jpg"
      storage_url = "http://s3.com/example/example.jpg"
      public_id = SecureRandom.hex
      s3_host = /s3\.amazonaws\.com/
      placeholder_color = SecureRandom.hex.first(6)

      stub_request(:put, s3_host).to_return(status: 404)

      cache = DownloadCache.new(image_url, public_id: public_id, preset_name: "primary")
      cache.save(storage_url:, image_url:, placeholder_color:)
      cache.copy
      refute cache.copied?
      assert_requested :put, s3_host
    end
  end
end