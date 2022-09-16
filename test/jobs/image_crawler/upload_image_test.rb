require "test_helper"
module Crawler
  module Image
    class UploadImageTest < ActiveSupport::TestCase
      def setup
        flush_redis
      end

      def test_should_upload
        public_id = SecureRandom.hex
        path = copy_support_file("image.jpeg")
        url = "http://example.com/image.jpg"

        stub_request(:put, /s3\.amazonaws\.com/)

        assert_equal 0, EntryImage.jobs.size
        UploadImage.new.perform(public_id, "primary", path, url, url)
        assert_equal 1, EntryImage.jobs.size

        download_cache = DownloadCache.new(url, public_id: public_id, preset_name: "primary")
        assert_equal("https:", download_cache.storage_url)
      end
    end
  end
end