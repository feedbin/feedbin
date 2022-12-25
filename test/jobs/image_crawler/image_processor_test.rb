require "test_helper"
module ImageCrawler
  class ImageProcessorTest < ActiveSupport::TestCase
    def test_should_get_image_size
      file = copy_support_file("image.jpeg")
      image = ImageProcessor.new(file, target_width: 542, target_height: 304, crop: :smart_crop)
      assert_equal(image.width, 640)
      assert_equal(image.height, 828)
      assert_equal(542, image.resized.width)
      assert_equal(701, image.resized.height)
    end

    def test_should_get_face_location
      file = copy_support_file("image.jpeg")
      image = ImageProcessor.new(file, target_width: 542, target_height: 304, crop: :smart_crop)

      assert_equal(462, image.average_face_position("y", File.new(file)))
    end

    def test_should_crop
      file = copy_support_file("image.jpeg")
      image = ImageProcessor.new(file, target_width: 542, target_height: 304, crop: :smart_crop)
      cropped_path = image.crop!
      assert_equal(542, image.final_width)
      assert_equal(304, image.final_height)
      assert cropped_path.include?(".jpg")
      FileUtils.rm cropped_path
    end

    def test_should_crop
      file = copy_support_file("image.jpeg")
      image = ImageProcessor.new(file, target_width: 400, target_height: 400, crop: :limit_crop)
      cropped_path = image.crop!
      assert_equal(309, image.final_width)
      assert_equal(400, image.final_height)
      assert cropped_path.include?(".jpg")
      FileUtils.rm cropped_path
    end

    def test_should_return_same_size_image
      file = copy_support_file("image.jpeg")
      image = ImageProcessor.new(file, target_width: 640, target_height: 828, crop: :smart_crop)
      cropped_path = image.crop!
      assert_equal(640, image.final_width)
      assert_equal(828, image.final_height)
      assert cropped_path.include?(".jpg")
    end
  end
end