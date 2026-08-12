require "test_helper"
module ImageCrawler
  module Processor
    class CropperTest < ActiveSupport::TestCase
      def test_should_get_image_size
        file = copy_support_file("image.jpeg")
        image = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)
        assert_equal(image.source.width, 640)
        assert_equal(image.source.height, 828)
        assert_equal(542, image.proposed_size.width)
        assert_equal(701, image.proposed_size.height)
      end

      def test_should_get_face_location
        file = copy_support_file("image.jpeg")
        image = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)
        assert_equal(462, image.average_face_position("y", File.new(file)))
      end

      # "I found nothing" and "I found something I cannot fully describe" are
      # both ordinary answers from a face detector, and neither is a position.
      def test_should_have_no_face_position_when_pigo_reports_nothing_usable
        {
          "no faces detected" => "[]",
          "face row without a size" => '[{"face":{"x":10}}]',
          "face row without an axis" => '[{"face":{"size":10}}]'
        }.each do |description, output|
          file = copy_support_file("image.jpeg")
          cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)

          Open3.stub(:capture3, [output, "", OpenStruct.new(success?: true)]) do
            assert_nil(cropper.average_face_position("x", File.new(file)), description)
          end
        end
      end

      def test_should_crop
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)
        image = cropper.crop!
        assert_equal(542, image.width)
        assert_equal(304, image.height)
        assert image.file.include?(".jpg")
        FileUtils.rm image.file
      end

      def test_should_crop
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :limit_crop, extension: "jpeg", width: 400, height: 400)
        image = cropper.crop!
        assert_equal(309, image.width)
        assert_equal(400, image.height)
        assert image.file.include?(".jpg")
        FileUtils.rm image.file
      end

      def test_should_return_same_size_image
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 640, height: 828)
        image = cropper.crop!
        assert_equal(640, image.width)
        assert_equal(828, image.height)
        assert image.file.include?(".jpg")
        FileUtils.rm image.file
      end

      def test_should_validate_conditionally
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 6000, height: 6000)
        refute cropper.valid?(true)
        assert cropper.valid?(false)
      end

      def test_should_return_png
        file = copy_support_file("image.png")
        cropper = Processor::Cropper.new(file, crop: :limit_crop, extension: "png", width: 400, height: 400)
        image = cropper.crop!
        assert image.file.end_with?(".png")
        FileUtils.rm image.file
      end

      def test_should_return_jpg
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :limit_crop, extension: "png", width: 400, height: 400)
        image = cropper.crop!
        assert image.file.end_with?(".jpg")
        FileUtils.rm image.file
      end

      def test_should_return_original
        file = copy_support_file("image.png")
        cropper = Processor::Cropper.new(file, crop: :limit_crop, extension: "png", width: 6000, height: 6000)
        image = cropper.crop!

        original_fingerprint = Digest::SHA1.hexdigest(File.read(file))
        cropped_fingerprint = Digest::SHA1.hexdigest(File.read(image.file))

        assert_equal(original_fingerprint, cropped_fingerprint)

        FileUtils.rm image.file
      end
    end
  end
end