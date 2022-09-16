require "test_helper"
module Crawler
  module Image
    class ImageTest < ActiveSupport::TestCase
      def test_should_get_image_size
        file = copy_support_file("image.jpeg")
        image = ImageProcessor.new(file, target_width: 542, target_height: 304)
        assert_equal(image.width, 640)
        assert_equal(image.height, 828)
        assert_equal(542, image.resized.width)
        assert_equal(701, image.resized.height)
      end

      def test_should_get_face_location
        file = copy_support_file("image.jpeg")
        image = ImageProcessor.new(file, target_width: 542, target_height: 304)

        assert_equal(462, image.average_face_position("y", File.new(file)))
      end

      def test_should_crop
        file = copy_support_file("image.jpeg")
        image = ImageProcessor.new(file, target_width: 542, target_height: 304)
        cropped_path = image.smart_crop
        assert cropped_path.include?(".jpg")
        FileUtils.rm cropped_path
      end

      def test_should_return_same_size_image
        file = copy_support_file("image.jpeg")
        image = ImageProcessor.new(file, target_width: 640, target_height: 828)
        cropped_path = image.smart_crop
        assert cropped_path.include?(".jpg")
      end
    end
  end
end