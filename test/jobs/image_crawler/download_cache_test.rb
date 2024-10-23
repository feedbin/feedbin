require "test_helper"
module ImageCrawler
  class DownloadCacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def build_image
      cache_key           = SecureRandom.hex
      id                  = SecureRandom.hex
      download_path       = copy_support_file("image.jpeg")
      processed_path      = download_path
      original_url        = "http://example.com/image.jpg"
      final_url           = "http://example.com/redirect/image.jpg"
      placeholder_color   = "0867e2"
      width               = 300
      height              = 200
      storage_url         = "http://s3.com/example/example.jpg"
      preset_name         = "primary"
      processed_extension = "jpg"
      provider            = ::Image.providers[:entry_content]
      provider_id         = 1
      Image.new(id:, preset_name:, download_path:, original_url:, final_url:, processed_path:, width:, height:, placeholder_color:, storage_url:, processed_extension:, provider:, provider_id:)
    end

    def build_duplicate_image(original_url)
      Image.new_with_attributes(
        id: SecureRandom.hex,
        preset_name: "primary",
        image_urls: [original_url],
        provider: ::Image.providers[:entry_content],
        provider_id: 1
      )
    end

    def test_should_save_data
      image = build_image
      cache = DownloadCache.save(image)

      image_two = build_duplicate_image(image.original_url)

      cache = DownloadCache.new(image.original_url, image_two)
      assert_equal(image.storage_url, cache.cached_image.storage_url)
      assert_equal(image.final_url, cache.cached_image.final_url)
      assert_equal(image.placeholder_color, cache.cached_image.placeholder_color)
    end

    def test_should_copy_existing_image
      stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

      image = build_image

      image_two = build_duplicate_image(image.original_url)

      cache = DownloadCache.new(image.original_url, image_two)
      refute cache.copied?

      cache.save(image)

      cache = DownloadCache.new(image.original_url, image_two)
      cache.copy

      assert cache.copied?
      assert cache.storage_url.include?(image_two.id)
      assert_equal(image.width, cache.cached_image.width)
      assert_equal(image.height, cache.cached_image.height)
    end

    def test_should_fail_to_copy_missing_image
      s3_host = /s3\.amazonaws\.com/

      stub_request(:put, s3_host).to_return(status: 404)

      image = build_image

      image_two = build_duplicate_image(image.original_url)

      DownloadCache.save(image)

      cache = DownloadCache.new(image.original_url, image_two)
      cache.copy

      refute cache.copied?
      assert_requested :put, s3_host
    end
  end
end