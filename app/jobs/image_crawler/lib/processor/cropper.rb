module ImageCrawler
  module Processor
    class Cropper
      CASCADE = Rails.root.join("lib/cascade/facefinder")
      PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
      PIGO_INSTALLED = File.executable?(PIGO)
      puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

      # Tuned mozjpeg options (~29% smaller than plain q80 at equal worst-case
      # quality) -- they need a mozjpeg-linked libjpeg; vips silently ignores
      # them otherwise. jpg, not webp: the stored file is the master (the
      # original is discarded), and a lossy webp master would make every
      # future format a lossy-to-lossy transcode. optimize_scans requires
      # interlace; interlace implies optimize_coding.
      JPG_SAVER = {
        quality: 76, background: 255, keep: :none,
        interlace: true, optimize_scans: true,
        trellis_quant: true, overshoot_deringing: true, quant_table: 3
      }.freeze

      # Icons are flat graphics with alpha; there is nothing to trade quality
      # against, so the only knob is dropping metadata.
      PNG_SAVER = {keep: :none}.freeze

      # Crops that encode their own output as png. The rest return geometry,
      # which crop! encodes as jpg.
      PNG_CROPS = %i[limit_png icon_crop]

      Size = Data.define(:width, :height)

      def initialize(file, crop:, width:, height:)
        @file   = file
        @crop   = crop
        @width  = width
        @height = height
      end

      def crop!
        return send(@crop) if PNG_CROPS.include?(@crop)
        Processed.from_pipeline(save_as(send(@crop), "jpg", JPG_SAVER))
      end

      def source
        @source ||= Vips::Image.new_from_file(ImageFormat.checked!(@file))
      end

      def valid?(validate)
        source.avg
        return false if @crop == :icon_crop && best_layer.nil?
        validate ? (source.width >= @width && source.height >= @height) : true
      rescue ::Vips::Error, ImageFormat::Unsupported
        false
      end

      def save_as(pipeline, format, saver)
        pipeline.convert(format).saver(**saver)
      end

      def pipeline(width, height)
        ImageProcessing::Vips
          .source(source)
          .resize_to_fill(width, height)
      end

      # Layer choice happens before any resizing. Memoized including the nil
      # case -- ||= would re-run the scan whenever the answer was "nothing".
      def best_layer
        return @best_layer if defined?(@best_layer)
        @best_layer = IconLayer.best(ImageFormat.checked!(@file))
      end

      def icon_crop
        scale_to_png(best_layer)
      end

      # icon_crop without layer selection: an avatar is one image, and
      # IconLayer's mostly-white heuristic would reject a dark logo on a
      # white background.
      def limit_png
        scale_to_png(source)
      end

      # Scale down to fit, never up, always PNG: a content-addressed preset
      # needs a fixed output format -- storage_path's extension and the
      # Content-Type both come from preset.format.
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
          constraint = @width
          max = proposed_size.width - @width
        else
          axis = "y"
          constraint = @height
          max = proposed_size.height - @height
        end

        if PIGO_INSTALLED && center = average_face_position(axis, save_as(image, "jpg", JPG_SAVER).call)
          point = {"x" => 0, "y" => 0}
          point[axis] = (center.to_f - constraint.to_f / 2.0).floor

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
          Size.new(width: proposed_width.to_i, height: proposed_height.to_i)
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
        FileUtils.rm_f(file.path)

        faces = if status.success?
          JSON.load(out)
        end

        return nil if faces.nil?

        # filter_map: inside a map, a bare `next` yields nil into the array
        # instead of skipping the element.
        result = faces.filter_map { |face| face.safe_dig("face") }.filter_map do |face|
          next if face[axis].nil? || face["size"].nil?
          face[axis] + face["size"] / 2
        end

        # [] (ran, found nothing) means the same as nil here: no position.
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