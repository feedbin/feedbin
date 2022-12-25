module ImageCrawler
  class ImageProcessor
    CASCADE = Rails.root.join("lib/cascade/facefinder")
    PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
    PIGO_INSTALLED = File.executable?(PIGO)
    puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

    attr_reader :path

    def initialize(file, target_width:, target_height:, crop:)
      @file          = file
      @target_width  = target_width
      @target_height = target_height
      @crop          = crop
    end

    def crop!
      send(@crop)
    end

    def source
      @source ||= Vips::Image.new_from_file(@file)
    end

    def valid?(validate)
      source.avg
      validate ? (original_width >= @target_width && original_height >= @target_height) : true
    rescue ::Vips::Error
      false
    end

    def original_width
      source.width
    end

    def original_height
      source.height
    end

    def resized_width
      processed_image&.width
    end

    def resized_height
      processed_image&.height
    end

    def placeholder_color
      hex = nil
      file = ImageProcessing::Vips
        .source(source)
        .resize_to_fill(1, 1, sharpen: false)
        .custom { |image|
          image.tap do |data|
            hex = data.getpoint(0, 0).map { |value| "%02x" % value }.first(3).join
          end
        }.call
      file.unlink
      hex
    end

    def pipeline(width, height)
      ImageProcessing::Vips
        .source(source)
        .resize_to_fill(width, height)
        .convert("jpg")
        .saver(strip: true, quality: 90)
    end

    def fill_crop
      pipeline(@target_width, @target_height).call(destination: persisted_path)
      persisted_path
    end

    def limit_crop
      ImageProcessing::Vips
        .source(source)
        .resize_to_limit(@target_width, @target_height)
        .convert("jpg")
        .saver(strip: true, quality: 90)
        .call(destination: persisted_path)
      persisted_path
    end

    def smart_crop
      return fill_crop if resize_too_small? || resize_just_right?

      image = pipeline(proposed_size.width, proposed_size.height)

      if proposed_size.width > @target_width
        axis = "x"
        contraint = @target_width
        max = proposed_size.width - @target_width
      else
        axis = "y"
        contraint = @target_height
        max = proposed_size.height - @target_height
      end

      if PIGO_INSTALLED && center = average_face_position(axis, image.call)
        point = {"x" => 0, "y" => 0}
        point[axis] = (center.to_f - contraint.to_f / 2.0).floor

        if point[axis] < 0
          point[axis] = 0
        elsif point[axis] > max
          point[axis] = max
        end

        image = image.crop(point["x"], point["y"], @target_width, @target_height)
      else
        image = image.resize_to_fill(@target_width, @target_height, crop: :attention)
      end

      image.call(destination: persisted_path)
      persisted_path
    end

    def proposed_size
      @proposed_size ||= begin
        proposed_width = @target_width.to_f

        width_proportion = original_width.to_f / original_height.to_f
        height_proportion = original_height.to_f / original_width.to_f

        proposed_height = proposed_width * height_proportion

        if proposed_height < @target_height
          proposed_height = @target_height.to_f
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

    def processed_image
      return unless File.exist?(persisted_path)
      @processed_image ||= Vips::Image.new_from_file(persisted_path)
    end

    def persisted_path
      @persisted_path ||= File.join(Dir.tmpdir, ["image_processed_", SecureRandom.hex, ".jpg"].join)
    end

    def resize_too_small?
      proposed_size.width < @target_width || proposed_size.height < @target_height
    end

    def resize_just_right?
      proposed_size.width == @target_width && proposed_size.height == @target_height
    end
  end
end
