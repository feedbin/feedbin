require 'rmagick'
require 'opencv'
include OpenCV

class ProcessedImage

  TARGET_WIDTH = 542.to_f
  WIDTH_RATIO = 16.to_f
  HEIGHT_RATIO = 9.to_f

  attr_reader :url

  def initialize(file)
    @file = file
    @url = nil
  end

  def ping
    @ping ||= Magick::Image.ping(@file.path).first
  end

  def width
    @width ||= ping.columns.to_f
  end

  def height
    @height ||= ping.rows.to_f
  end

  def valid?
    image_ratio = height / width
    target_ratio = HEIGHT_RATIO / WIDTH_RATIO
    width >= TARGET_WIDTH && image_ratio <= 1 && image_ratio >= target_ratio
  end

  def process
    success = false
    if valid?
      processed_image = Tempfile.new(["image-", ".jpg"])
      processed_image.close
      center = find_center_of_objects
      crop = crop_rectangle(center)

      image = Magick::Image.read(@file.path).first
      image = image.crop(crop[:x], crop[:y], crop[:width], crop[:height])
      image = image.resize_to_fit(TARGET_WIDTH)
      image.write(processed_image.path)

      processed_image.open
      uploader = EntryImageUploader.new
      uploader.store!(processed_image)
      processed_image.close(true)

      @url = uploader.url
      success = true
    end
    success
  end

  def find_center_of_objects
    data = "#{Rails.root}/lib/assets/haarcascade_frontalface_alt.xml"
    detector = CvHaarClassifierCascade::load(data)

    center = 0
    image = CvMat.load(@file.path)

    objects = detector.detect_objects(image)
    if objects.count > 0
      center = 0
      objects.each do |region|
        center += region.center.y
      end
      center = center / objects.count.to_f
    end

    center
  end

  def crop_rectangle(center)
    ratio = HEIGHT_RATIO / WIDTH_RATIO
    crop_height = (ratio * width).floor
    half_crop_height = crop_height / 2
    y_position = center - half_crop_height

    if y_position <= 0
      y_position = 0
    elsif center + half_crop_height > height
      y_position = height - crop_height
    end

    {x: 0, y: y_position, width: width, height: crop_height}
  end

end