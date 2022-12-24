require "test_helper"
module ImageCrawler
  class ProcessTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_enqueue_upload
      public_id = SecureRandom.hex
      path = copy_support_file("image.jpeg")
      url = "http://example.com/image.jpg"

      assert_difference -> { Upload.jobs.size }, +1 do
        Process.new.perform(public_id, "primary", path, url, url, [])
      end

      assert_equal(public_id, Upload.jobs.first["args"][0])
      assert_equal("primary", Upload.jobs.first["args"][1])
      assert(Upload.jobs.first["args"][2].include?("image_processed"), "Should contain path to image")
      assert_equal(url, Upload.jobs.first["args"][3])
      assert_equal(url, Upload.jobs.first["args"][4])
      assert_equal(6, Upload.jobs.first["args"][5].length)
    end

    def test_should_enqueue_find
      public_id = SecureRandom.hex
      path = Tempfile.new.path
      url = "http://example.com/image.jpg"
      all_urls = ["http://example.com/image_2.jpg", "http://example.com/image_3.jpg"]

      assert_difference -> { FindCritical.jobs.size }, +1 do
        Process.new.perform(public_id, "primary", path, url, url, all_urls)
      end

      assert_equal([public_id, "primary", all_urls], FindCritical.jobs.first["args"])
    end
  end
end