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

      def test_should_reject_content_that_is_not_an_image
        file = File.join(Dir.tmpdir, SecureRandom.hex)
        File.binwrite(file, "%!PS-Adobe-3.0\n/Times findfont")

        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)

        assert_not cropper.valid?(true)
        assert_raises ImageFormat::Unsupported do
          cropper.source
        end

        FileUtils.rm file
      end

      def test_should_crop_pair_in_both_formats
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :fill_crop, extension: "jpeg", width: 542, height: 304)
        pair = cropper.crop_pair!

        assert_equal(542, pair[:jpg].width)
        assert_equal(304, pair[:jpg].height)
        assert pair[:jpg].file.end_with?(".jpg")
        assert_equal(:jpeg, ImageFormat.detect(pair[:jpg].file))

        assert_equal(542, pair[:webp].width)
        assert_equal(304, pair[:webp].height)
        assert pair[:webp].file.end_with?(".webp")
        assert_equal(:webp, ImageFormat.detect(pair[:webp].file))
        assert pair[:webp].size.positive?

        FileUtils.rm pair[:jpg].file
        FileUtils.rm pair[:webp].file
      end

      def test_should_crop_pair_with_smart_crop
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)
        pair = cropper.crop_pair!

        assert_equal(:jpeg, ImageFormat.detect(pair[:jpg].file))
        assert_equal(:webp, ImageFormat.detect(pair[:webp].file))
        assert_equal(pair[:jpg].width, pair[:webp].width)
        assert_equal(pair[:jpg].height, pair[:webp].height)

        FileUtils.rm pair[:jpg].file
        FileUtils.rm pair[:webp].file
      end

      def test_should_render_an_icon_as_png_from_the_best_layer
        file = copy_support_file("favicon.ico")
        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "ico", width: 32, height: 32)

        assert cropper.valid?(false)
        image = cropper.crop!

        assert_equal(:png, ImageFormat.detect(image.file))
        assert_operator image.width, :<=, 32
        assert_operator image.height, :<=, 32
        FileUtils.rm image.file
      end

      # limit, not fit: upscaling fabricates no detail, it only makes a bigger
      # file that is equally soft. A 200x200 recipe applied to a small source
      # must leave the source's dimensions alone.
      def test_should_never_upscale_an_icon
        file = copy_support_file("favicon.ico")
        layer_width = IconLayer.best(file).width

        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "ico", width: 200, height: 200)
        image = cropper.crop!

        assert_operator layer_width, :<, 200, "fixture must be smaller than the target for this to prove anything"
        assert_equal layer_width, image.width
        FileUtils.rm image.file
      end

      # Plenty of sites now ship an SVG favicon. It rasterizes at the preset's
      # size like any other input -- one rendition per variant, no format
      # branch -- which also proves librsvg is reachable through vips.
      def test_should_rasterize_an_svg_icon
        file = File.join(Dir.tmpdir, "#{SecureRandom.hex}.svg")
        File.write(file, %(<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><rect width="512" height="512" fill="#0867e2"/></svg>))

        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "svg", width: 32, height: 32)
        assert cropper.valid?(false)
        image = cropper.crop!

        assert_equal(:png, ImageFormat.detect(image.file))
        assert_equal(32, image.width)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      def test_should_be_invalid_when_no_icon_layer_is_usable
        file = copy_support_file("favicon-blank.ico")
        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "ico", width: 32, height: 32)

        assert_not cropper.valid?(false)
      end
    end
  end
end