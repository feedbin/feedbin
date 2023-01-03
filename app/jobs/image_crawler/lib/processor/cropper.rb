module ImageCrawler
  module Processor
    class Cropper
      CASCADE = Rails.root.join("lib/cascade/facefinder")
      PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
      PIGO_INSTALLED = File.executable?(PIGO)
      INVALID_COLORS = ["000000", "ffffff", nil]
      puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

      attr_reader :path

      def initialize(file, crop:, extension:, width:, height:)
        @file      = file
        @crop      = crop
        @extension = extension
        @width     = width
        @height    = height
      end

      def crop!
        send(@crop)
      end

      def source
        @source ||= Vips::Image.new_from_file(@file)
      end

      def load_layer(page)
        begin
          Vips::Image.new_from_file(@file, page: page)
        rescue Vips::Error
          Vips::Image.new_from_file(@file)
        end
      rescue Vips::Error
        nil
      end

      def size
        File.size(@file)
      end

      def valid?(validate)
        source.avg
        validate ? (source.width >= @width && source.height >= @height) : true
      rescue ::Vips::Error
        false
      end

      def pipeline(width, height)
        ImageProcessing::Vips
          .source(source)
          .resize_to_fill(width, height)
          .convert("jpg")
          .saver(strip: true, quality: 90)
      end

      def limit_crop
        extension = source.has_alpha? ? "png" : "jpg"
        image = ImageProcessing::Vips
          .source(source)
          .resize_to_limit(@width, @height)
          .convert(extension)
          .saver(strip: true, quality: 90)

        result = Processed.from_pipeline(image)

        # if the original is smaller than the resized, just use that one
        if result.size > size && source.width <= @width && source.height <= @height && ["png", "jpg"].include?(@extension)
          return Processed.from_file(@file, @extension)
        end
        result
      end

      def favicon_crop
        layer = best_layer

        return unless layer.present?

        smallest = [layer.width, layer.height, @width, @height].min

        image = ImageProcessing::Vips
          .source(layer)
          .resize_to_fill(smallest, smallest)
          .saver(strip: true)
          .convert("png")

        Processed.from_pipeline(image)
      end

      def fill_crop
        image = pipeline(@width, @height)
        Processed.from_pipeline(image)
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

        if PIGO_INSTALLED && center = average_face_position(axis, image.call)
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

        Processed.from_pipeline(image)
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

        result = faces.filter_map { |face| face.safe_dig("face") }.map do |face|
          next if face[axis].nil? || face["size"].nil?
          face[axis] + face["size"] / 2
        end

        (result.sum(0.0) / result.size).to_i
      end

      def resize_too_small?
        proposed_size.width < @width || proposed_size.height < @height
      end

      def resize_just_right?
        proposed_size.width == @width && proposed_size.height == @height
      end

      def best_layer
        (0..4)
          .filter_map { load_layer(_1) }
          .uniq       { _1.size }
          .sort_by    { _1.size.first * -1 }
          .find       { !INVALID_COLORS.include?(color(_1)) }
      end

      def color(source)
        hex = nil
        file = ImageProcessing::Vips
          .source(source)
          .resize_to_fill(1, 1, sharpen: false)
          .custom { |image|
            image.tap do |data|
              hex = data.getpoint(0, 0).map { "%02x" % _1 }.first(3).join
            end
          }
          .call
        file.unlink
        hex
      end
    end
  end
end