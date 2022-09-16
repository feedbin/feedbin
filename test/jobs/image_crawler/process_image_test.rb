require "test_helper"
module Crawler
  module Image
    class ProcessImageTest < ActiveSupport::TestCase
      def setup
        flush_redis
      end

      def test_should_enqueue_upload
        public_id = SecureRandom.hex
        path = copy_support_file("image.jpeg")
        url = "http://example.com/image.jpg"

        assert_equal 0, UploadImage.jobs.size
        ProcessImage.new.perform(public_id, "primary", path, url, url, [])
        assert_equal 1, UploadImage.jobs.size

        assert_equal(public_id, UploadImage.jobs.first["args"].first)
        assert_equal(url, UploadImage.jobs.first["args"].last)
      end

      def test_should_enqueue_find
        public_id = SecureRandom.hex
        path = Tempfile.new.path
        url = "http://example.com/image.jpg"
        all_urls = ["http://example.com/image_2.jpg", "http://example.com/image_3.jpg"]

        assert_equal 0, FindImageCritical.jobs.size
        ProcessImage.new.perform(public_id, "primary", path, url, url, all_urls)
        assert_equal 1, FindImageCritical.jobs.size

        assert_equal([public_id, "primary", all_urls], FindImageCritical.jobs.first["args"])
      end
    end
  end
end