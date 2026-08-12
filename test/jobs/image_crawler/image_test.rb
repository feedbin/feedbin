require "test_helper"

module ImageCrawler
  class ImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    test "ignores unknown attributes" do
      image = Image.new("id" => "abc", "attribute_from_the_future" => "value")
      assert_equal "abc", image.id
    end

    test "sets known attributes" do
      image = Image.new("id" => "abc", "preset_name" => "primary", "image_urls" => ["http://example.com/a.jpg"])
      assert_equal "primary", image.preset_name
      assert_equal ["http://example.com/a.jpg"], image.image_urls
    end
  end
end
