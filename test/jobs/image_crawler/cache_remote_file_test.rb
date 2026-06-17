require "test_helper"

module ImageCrawler
  class CacheRemoteFileTest < ActiveSupport::TestCase
    def setup
      @url = "bc5431c75680852f26ff34e4688af32b-icon"
      @image = {
        "original_url" => "https://example.com/avatar.jpg",
        "processed_url" => "https://files.example.com/bc5/bc5431c75680852f26ff34e4688af32b-icon.jpg",
        "width" => 240,
        "height" => 240,
      }
    end

    test "creates a remote file" do
      assert_difference "RemoteFile.count", 1 do
        CacheRemoteFile.new.perform(@url, @image)
      end

      remote_file = RemoteFile.find_by(fingerprint: "bc5431c75680852f26ff34e4688af32b")
      assert_equal @image["original_url"], remote_file.original_url
      assert_equal @image["processed_url"], remote_file.storage_url
      assert_equal @image["width"], remote_file.width
      assert_equal @image["height"], remote_file.height
    end

    test "is idempotent when the fingerprint already exists" do
      CacheRemoteFile.new.perform(@url, @image)

      assert_no_difference "RemoteFile.count" do
        assert_nothing_raised do
          CacheRemoteFile.new.perform(@url, @image)
        end
      end
    end
  end
end
