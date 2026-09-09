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

      # The mozjpeg options are the whole reason the entry presets can leave
      # webp: they are what claws back most of the bytes webp was saving. vips
      # accepts and ignores them on a libjpeg without mozjpeg, so assert they
      # actually took effect rather than that they were merely passed.
      def test_should_apply_the_mozjpeg_savings
        file = copy_support_file("image.jpeg")
        tuned = Processor::Cropper.new(file, crop: :fill_crop, extension: "jpeg", width: 542, height: 304).crop!

        plain = ImageProcessing::Vips
          .source(Vips::Image.new_from_file(copy_support_file("image.jpeg")))
          .resize_to_fill(542, 304)
          .convert("jpg")
          .saver(strip: true, quality: 80, background: 255)
          .call

        assert_operator tuned.size, :<, File.size(plain.path),
          "tuned jpg is not smaller than a plain quality: 80 -- is this libvips linked against mozjpeg?"

        FileUtils.rm tuned.file
      end

      def test_should_crop_to_a_single_jpg
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :fill_crop, extension: "jpeg", width: 542, height: 304)
        cropped = cropper.crop!

        assert_equal(542, cropped.width)
        assert_equal(304, cropped.height)
        assert cropped.file.end_with?(".jpg")
        assert_equal(:jpeg, ImageFormat.detect(cropped.file))
        assert cropped.size.positive?

        FileUtils.rm cropped.file
      end

      def test_should_crop_to_a_single_jpg_with_smart_crop
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)
        cropped = cropper.crop!

        assert_equal(:jpeg, ImageFormat.detect(cropped.file))
        assert_equal(542, cropped.width)
        assert_equal(304, cropped.height)

        FileUtils.rm cropped.file
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

      def test_should_scale_down_to_png_without_selecting_a_layer
        file = copy_support_file("image.png")
        cropper = Processor::Cropper.new(file, crop: :limit_png, extension: "png", width: 200, height: 200)
        image = cropper.crop!

        assert_equal(200, image.width)
        assert_equal(117, image.height)
        assert_equal("png", image.extension)
        assert_equal(:png, ImageFormat.detect(image.file))
        FileUtils.rm image.file
      end

      # limit, not fit: upscaling fabricates no detail, it only makes a bigger
      # file that is equally soft. A channel that has never uploaded anything
      # larger than the 88x88 default thumbnail stays 88x88.
      def test_should_not_upscale_a_small_source
        file = write_solid_png(88, 88, [200, 100, 50])
        cropper = Processor::Cropper.new(file, crop: :limit_png, extension: "png", width: 200, height: 200)
        image = cropper.crop!

        assert_equal(88, image.width)
        assert_equal(88, image.height)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      # icon_crop rejects mostly-white sources (IconLayer padding
      # heuristic); a dark-logo-on-white avatar must not be rejected.
      def test_should_accept_a_white_source_that_icon_crop_rejects
        file = write_solid_png(300, 300, [255, 255, 255])

        refute Processor::Cropper.new(file, crop: :icon_crop, extension: "png", width: 200, height: 200).valid?(false)

        cropper = Processor::Cropper.new(file, crop: :limit_png, extension: "png", width: 200, height: 200)
        assert cropper.valid?(false)

        image = cropper.crop!
        assert_equal(200, image.width)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      # channel_avatar and touch_icon are both 200x200 png, so identical
      # source bytes share one object -- correct only while the two recipes
      # agree on single-layer sources. If this fails, the presets need
      # distinct storage keys. Multi-page sources differ by design
      # (IconLayer.best vs page 0), which is why limit_png exists.
      def test_icon_crop_and_limit_png_agree_on_a_single_layer_source
        icon_file  = copy_support_file("image.png")
        limit_file = copy_support_file("image.png")

        icon  = Processor::Cropper.new(icon_file, crop: :icon_crop, extension: "png", width: 200, height: 200).crop!
        limit = Processor::Cropper.new(limit_file, crop: :limit_png, extension: "png", width: 200, height: 200).crop!

        assert_equal icon.fingerprint, limit.fingerprint
        FileUtils.rm icon.file
        FileUtils.rm limit.file
      end

      # icon_crop is a limit crop: a 200x200 preset leaves a 180x180 source
      # alone rather than upscaling.
      def test_icon_crop_should_not_upscale_a_small_source
        file = write_solid_png(180, 180, [40, 90, 200])
        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "png", width: 200, height: 200)
        image = cropper.crop!

        assert_equal(180, image.width)
        assert_equal(180, image.height)
        assert_equal("png", image.extension)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      # Not private: a `private` section would silently swallow any test
      # appended after it.
      def write_solid_png(width, height, rgb)
        path = File.join(Dir.tmpdir, "#{SecureRandom.hex}.png")
        Vips::Image.black(width, height)
          .linear(1, rgb.first)
          .cast(:uchar)
          .bandjoin(rgb.drop(1))
          .copy(interpretation: :srgb)
          .write_to_file(path)
        path
      end
    end
  end
end