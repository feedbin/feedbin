require "test_helper"
module ImageCrawler
  class DownloadCacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def build_image
      cache_key         = SecureRandom.hex
      id                = SecureRandom.hex
      download_path     = copy_support_file("image.jpeg")
      processed_path    = download_path
      original_url      = "http://example.com/image.jpg"
      final_url         = "http://example.com/redirect/image.jpg"
      placeholder_color = "0867e2"
      width             = 300
      height            = 200
      storage_url       = "http://s3.com/example/example.jpg"
      preset_name       = "primary"
      Image.new_from_hash(id:, preset_name:, download_path:, original_url:, final_url:, processed_path:, width:, height:, placeholder_color:, storage_url:)
    end

    def test_should_save_data
      image = build_image
      cache = DownloadCache.save(image)

      cache = DownloadCache.new(image.original_url, image.preset_name)
      assert_equal(image.storage_url, cache.image.storage_url)
      assert_equal(image.final_url, cache.image.final_url)
      assert_equal(image.placeholder_color, cache.image.placeholder_color)
    end

    def test_should_copy_existing_image
      stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

      image = build_image
      cache = DownloadCache.new(image.original_url, image.preset_name)
      refute cache.copied?

      cache.save(image)

      cache = DownloadCache.new(image.original_url, image.preset_name)
      cache.copy

      assert cache.copied?
      assert cache.storage_url.include?(image.id)
      assert_equal(image.width, cache.image.width)
      assert_equal(image.height, cache.image.height)
    end

    def test_should_fail_to_copy_missing_image
      s3_host = /s3\.amazonaws\.com/

      stub_request(:put, s3_host).to_return(status: 404)

      image = build_image

      DownloadCache.save(image)

      cache = DownloadCache.new(image.original_url, image.preset_name)
      cache.copy

      refute cache.copied?
      assert_requested :put, s3_host
    end
  end
end