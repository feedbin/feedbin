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

      # Every pixel transparent is blank whatever colour the pixels carry: the
      # alpha decides, not the RGB under it.
      def test_should_return_nil_for_a_fully_transparent_layer
        [[0, 0, 0], [200, 30, 30]].each do |rgb|
          path = png(rgb + [0])
          assert_nil IconLayer.best(path), "transparent #{rgb.inspect}"
        ensure
          FileUtils.rm_f path
        end
      end

      # Plenty of logos are black. Only the alpha separates one from a blank
      # layer.
      def test_should_keep_an_opaque_black_layer
        path = png([0, 0, 0, 255])
        assert_not_nil IconLayer.best(path)
      ensure
        FileUtils.rm_f path
      end

      def test_should_return_nil_for_a_white_layer_of_any_opacity
        [[255, 255, 255, 255], [255, 255, 255, 128]].each do |rgba|
          path = png(rgba)
          assert_nil IconLayer.best(path), "white #{rgba.inspect}"
        ensure
          FileUtils.rm_f path
        end
      end

      def test_should_return_nil_for_a_file_vips_cannot_open
        path = File.join(Dir.tmpdir, SecureRandom.hex)
        File.binwrite(path, "not an image at all")

        assert_nil IconLayer.best(path)
      ensure
        FileUtils.rm_f path
      end

      # A 64x64 sRGB png filled with one RGBA value. Built per test, never at
      # class-body level: vips in the parent process wedges forked workers.
      def png(rgba)
        path = File.join(Dir.tmpdir, "#{SecureRandom.hex}.png")
        Vips::Image.black(64, 64).new_from_image(rgba).copy(interpretation: :srgb).cast(:uchar).pngsave(path)
        path
      end
    end
  end
end
