require "test_helper"

module ImageCrawler
  module Processor
    class IconLayerTest < ActiveSupport::TestCase
      def test_should_pick_the_largest_usable_layer
        layer = IconLayer.best(support_file("favicon.ico"))

        assert_not_nil layer
        assert_operator layer.width, :>=, 16
      end

      # A favicon whose every layer is blank is not a favicon. Returning nil
      # here is what lets the crawler move on to the next candidate instead of
      # storing an empty square.
      def test_should_return_nil_when_every_layer_is_blank
        assert_nil IconLayer.best(support_file("favicon-blank.ico"))
      end

      def test_should_return_nil_for_a_file_vips_cannot_open
        path = File.join(Dir.tmpdir, SecureRandom.hex)
        File.binwrite(path, "not an image at all")

        assert_nil IconLayer.best(path)
      ensure
        FileUtils.rm_f path
      end
    end
  end
end
