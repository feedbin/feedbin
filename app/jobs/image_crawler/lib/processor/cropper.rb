module ImageCrawler
  module Processor
    class Cropper
      CASCADE = Rails.root.join("lib/cascade/facefinder")
      PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
      PIGO_INSTALLED = File.executable?(PIGO)
      puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

      JPG_SAVER  = {strip: true, quality: 80, background: 255}.freeze

      # smart_subsample computes the chroma planes in linear light, which is
      # what stops saturated edges — white text on red, mostly — from bleeding.
      # It costs ~4% more bytes and buys enough quality to pay for the Q cut:
      # measured over 89 real entry images, this pair is 7.4% smaller than the
      # old quality: 65 and still better on median, p10 and worst case, with the
      # images scoring under ssimulacra2 60 down from 8 to 2. effort: 6 is pure
      # size savings at fixed Q. See tmp/images/README.md.
      WEBP_SAVER = {strip: true, quality: 58, effort: 6, smart_subsample: true, smart_deblock: true}.freeze

      attr_reader :path

      def initialize(file, crop:, extension:, width:, height:)
        @file      = file
        @crop      = crop
        @extension = extension
        @width     = width
        @height    = height
      end

      def crop!
        return limit_crop if @crop == :limit_crop
        Processed.from_pipeline(save_as(geometry, "jpg", JPG_SAVER))
      end

      # One geometry pass, two encodings. Only the fill/smart crops support
      # this; limit_crop (icons) picks its own format and may keep the
      # original file, and never dual-writes.
      def crop_pair!
        cropped = geometry
        {
          jpg:  Processed.from_pipeline(save_as(cropped, "jpg", JPG_SAVER)),
          webp: Processed.from_pipeline(save_as(cropped, "webp", WEBP_SAVER))
        }
      end

      def source
        @source ||= Vips::Image.new_from_file(ImageFormat.checked!(@file))
      end

      def size
        File.size(@file)
      end

      def valid?(validate)
        source.avg
        validate ? (source.width >= @width && source.height >= @height) : true
      rescue ::Vips::Error, ImageFormat::Unsupported
        false
      end

      def geometry
        @geometry ||= send(@crop)
      end

      def save_as(pipeline, format, saver)
        pipeline.convert(format).saver(**saver)
      end

      def pipeline(width, height)
        ImageProcessing::Vips
          .source(source)
          .resize_to_fill(width, height)
      end

      def limit_crop
        extension = source.has_alpha? ? "png" : "jpg"
        image = ImageProcessing::Vips
          .source(source)
          .resize_to_limit(@width, @height)
          .convert(extension)
          .saver(strip: true, quality: 80)

        result = Processed.from_pipeline(image)

        # if the original is smaller than the resized, just use that one
        if result.size > size && source.width <= @width && source.height <= @height && ["png", "jpg"].include?(@extension)
          File.unlink(result.file)
          return Processed.from_file(@file, @extension)
        end
        result
      end

      def fill_crop
        pipeline(@width, @height)
      end

      def smart_crop
        return fill_crop if resize_too_small? || resize_just_right?

        image = pipeline(proposed_size.width, proposed_size.height)

        if proposed_size.width > @width
          axis = "x"
          contraint = @width
          max = proposed_size.width - @width
        else
          axis = "y"
          contraint = @height
          max = proposed_size.height - @height
        end

        if PIGO_INSTALLED && center = average_face_position(axis, save_as(image, "jpg", JPG_SAVER).call)
          point = {"x" => 0, "y" => 0}
          point[axis] = (center.to_f - contraint.to_f / 2.0).floor

          if point[axis] < 0
            point[axis] = 0
          elsif point[axis] > max
            point[axis] = max
          end

          image = image.crop(point["x"], point["y"], @width, @height)
        else
          image = image.resize_to_fill(@width, @height, crop: :attention)
        end

        image
      end

      def proposed_size
        @proposed_size ||= begin
          proposed_width = @width.to_f

          width_proportion = source.width.to_f / source.height.to_f
          height_proportion = source.height.to_f / source.width.to_f

          proposed_height = proposed_width * height_proportion

          if proposed_height < @height
            proposed_height = @height.to_f
            proposed_width = proposed_height * width_proportion
          end
          OpenStruct.new({width: proposed_width.to_i, height: proposed_height.to_i})
        end
      end

      def average_face_position(axis, file)
        params = {
          pigo: Shellwords.escape(PIGO),
          image: Shellwords.escape(file.path),
          cascade: Shellwords.escape(CASCADE)
        }
        command = "%<pigo>s -in %<image>s -out empty -cf %<cascade>s -scale 1.2 -json -"
        out, _, status = Open3.capture3(command % params)
        begin
          File.unlink(file)
        rescue
          Errno::ENOENT
        end

        faces = if status.success?
          JSON.load(out)
        end

        return nil if faces.nil?

        # filter_map on both: inside a map, a bare `next` yields nil into the
        # array rather than skipping the element, so the guard below was turning
        # a malformed face row into a nil that [nil].sum could not add.
        result = faces.filter_map { |face| face.safe_dig("face") }.filter_map do |face|
          next if face[axis].nil? || face["size"].nil?
          face[axis] + face["size"] / 2
        end

        # A detector that ran and found nothing returns [], which is a different
        # answer from the nil above but has the same meaning here: no position.
        return nil if result.empty?

        (result.sum(0.0) / result.size).to_i
      end

      def resize_too_small?
        proposed_size.width < @width || proposed_size.height < @height
      end

      def resize_just_right?
        proposed_size.width == @width && proposed_size.height == @height
      end
    end
  end
end