class Image
  attr_reader :path

  def initialize(file, target_width:, target_height:)
    @file = file
    @target_width = target_width
    @target_height = target_height
  end

  def valid?
    source.avg && width >= @target_width && height >= @target_height
  rescue ::Vips::Error
    false
  end

  def height
    source.height
  end

  def width
    source.width
  end

  def color
    hex = nil
    file = ImageProcessing::Vips
      .source(source)
      .resize_to_fill(1, 1, sharpen: false)
      .custom { |image|
        image.tap do |data|
          hex = data.getpoint(0, 0).map { |value| "%02x" % value }.join
        end
      }.call
    file.unlink
    hex
  end

  def source
    @source ||= Vips::Image.new_from_file(@file)
  end

  def pipeline(resized_width, resized_height)
    ImageProcessing::Vips
      .source(source)
      .resize_to_fill(resized_width, resized_height)
      .convert("jpg")
      .saver(strip: true, quality: 90)
  end

  def fill_crop
    pipeline(@target_width, @target_height).call(destination: persisted_path)
    persisted_path
  end

  def smart_crop
    return fill_crop if resize_too_small? || resize_just_right?

    image = pipeline(resized.width, resized.height)

    if resized.width > @target_width
      axis = "x"
      contraint = @target_width
      max = resized.width - @target_width
    else
      axis = "y"
      contraint = @target_height
      max = resized.height - @target_height
    end

    if center = average_face_position(axis, image.call)
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

  def resized
    @resized ||= begin
      resized_width = @target_width.to_f

      width_proportion = width.to_f / height.to_f
      height_proportion = height.to_f / width.to_f

      resized_height = resized_width * height_proportion

      if resized_height < @target_height
        resized_height = @target_height.to_f
        resized_width = resized_height * width_proportion
      end
      OpenStruct.new({width: resized_width.to_i, height: resized_height.to_i})
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

    result = faces.flat_map { |face| face.dig("face") }.map do |face|
      face[axis] + face["size"] / 2
    end

    (result.sum(0.0) / result.size).to_i
  end

  def persisted_path
    @persisted_path ||= File.join(Dir.tmpdir, ["image_processed_", SecureRandom.hex, ".jpg"].join)
  end

  def resize_too_small?
    resized.width < @target_width || resized.height < @target_height
  end

  def resize_just_right?
    resized.width == @target_width && resized.height == @target_height
  end
end
