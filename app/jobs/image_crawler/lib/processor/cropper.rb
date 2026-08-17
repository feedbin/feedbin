module ImageCrawler
  module Processor
    class Cropper
      CASCADE = Rails.root.join("lib/cascade/facefinder")
      PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
      PIGO_INSTALLED = File.executable?(PIGO)
      puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

      # The mozjpeg options, which need a mozjpeg-linked libjpeg -- verify that
      # before trusting the numbers, because vips accepts and ignores them
      # otherwise, with no error and no saving. Measured over 40 real entry
      # crops: these five alone are 16.5% smaller than a plain quality: 80, and
      # quant_table 3 takes it to 20.4%; the Q cut to 76 makes it 29.2%. Worst
      # case holds at a plain q80's (ssimulacra2 48.0 against 47.9) while the
      # median gives up 5.7, so the saving comes off the images with headroom
      # rather than the ones already struggling. See tmp/images/README.md.
      #
      # Not webp, though webp is both smaller and better at every setting
      # measured: whatever is stored is the master, since the original download
      # is discarded, and a lossy webp master makes every future format a
      # lossy-to-lossy transcode. jpg is the more universally transcodable
      # master, and the one API clients are known to handle.
      JPG_SAVER = {
        strip: true, quality: 76, background: 255,
        optimize_coding: true, interlace: true, trellis_quant: true,
        overshoot_deringing: true, optimize_scans: true, quant_table: 3
      }.freeze

      # Icons are flat graphics with alpha; there is nothing to trade quality
      # against, so the only knob is dropping metadata.
      PNG_SAVER = {strip: true}.freeze

      attr_reader :path

      def initialize(file, crop:, extension:, width:, height:)
        @file      = file
        @crop      = crop
        @extension = extension
        @width     = width
        @height    = height
      end

      # Crops that own their output format and return a finished Processed:
      # limit_crop picks png or jpg from the source's alpha and may keep the
      # original file untouched, and the png crops are always png. Everything
      # else is a geometry pass this encodes as jpg.
      SELF_ENCODING_CROPS = %i[limit_crop limit_png icon_crop]

      def crop!
        return send(@crop) if SELF_ENCODING_CROPS.include?(@crop)
        Processed.from_pipeline(save_as(geometry, "jpg", JPG_SAVER))
      end

      def source
        @source ||= Vips::Image.new_from_file(ImageFormat.checked!(@file))
      end

      def size
        File.size(@file)
      end

      def valid?(validate)
        source.avg
        return false if @crop == :icon_crop && best_layer.nil?
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

      # Multi-layer sources have no single "the image"; the layer choice is the
      # first real decision, so it happens before any resizing. Memoized
      # including the nil case -- ||= would re-run the whole layer scan every
      # time the answer was "nothing usable".
      def best_layer
        return @best_layer if defined?(@best_layer)
        @best_layer = IconLayer.best(ImageFormat.checked!(@file))
      end

      def icon_crop
        scale_to_png(best_layer)
      end

      # icon_crop without the layer selection: a YouTube channel avatar is
      # one image, not a container of candidates, and IconLayer's heuristics
      # would reject a perfectly good avatar for being mostly white (which
      # for an .ico means "padding around the real icon" and for an avatar
      # means "a dark logo on a white background").
      def limit_png
        scale_to_png(source)
      end

      # Scale down to fit the box, never up, and always emit PNG -- unlike
      # limit_crop, which picks png or jpg from the source's alpha channel
      # and may return the original file untouched. A content-addressed
      # preset needs a fixed output format, because storage_path's extension
      # and the R2 Content-Type both come from preset.format.
      def scale_to_png(input)
        image = ImageProcessing::Vips
          .source(input)
          .resize_to_limit(@width, @height)

        Processed.from_pipeline(save_as(image, "png", PNG_SAVER))
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