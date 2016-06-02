require 'rmagick'
require 'opencv' if ENV['RACK_ENV'] != 'test'

class ProcessedImage

  TARGET_WIDTH = 542.to_f

  attr_reader :url, :width, :height

  def initialize(file)
    @file = file
    @url = nil
  end

  def process
    success = false
    image = Magick::Image.read(@file).first
    image_file = Pathname.new(File.join(Dir.tmpdir, "#{SecureRandom.hex}.jpg"))
    resized_file = Pathname.new(File.join(Dir.tmpdir, "#{SecureRandom.hex}.jpg"))
    if valid?
      geometry = Magick::Geometry.new(TARGET_WIDTH, target_height, 0, 0, Magick::MinimumGeometry)
      image.change_geometry!(geometry) do |new_width, new_height|
        image.resize!(new_width, new_height)
      end
      image.write(resized_file.to_s)
      crop = find_best_crop(image.columns, image.rows, resized_file.to_s)
      image.crop!(crop[:x], crop[:y], crop[:width], crop[:height])
      sharpened_image = image.unsharp_mask(1.5)
      sharpened_image.write(image_file.to_s)
      @url = upload(image_file)
      @width = crop[:width]
      @height = crop[:height]
      success = true
    end
    success
  ensure
    image && image.destroy!
    sharpened_image && sharpened_image.destroy!
    resized_file && File.exist?(resized_file) && File.delete(resized_file)
    image_file && File.exist?(image_file) && File.delete(image_file)
  end

  private

  def ping
    @ping ||= Magick::Image.ping(@file).first
  end

  def original_width
    @original_width ||= ping.columns.to_f
  end

  def original_height
    @original_height ||= ping.rows.to_f
  end

  def ratio
    @ratio ||= original_height / original_width
  end

  def landscape?
    ratio <= 1
  end

  def panoramic?
    landscape? && ratio < target_ratio
  end

  def target_ratio
    @target_ratio ||= begin
      width_ratio = 16
      height_ratio = 9
      height_ratio.to_f / width_ratio.to_f
    end
  end

  def target_height
    @target_height ||= begin
      (target_ratio * TARGET_WIDTH).floor
    end
  end

  def valid?
    original_width >= TARGET_WIDTH && original_height >= target_height
  end

  def upload(file)
    uploader = EntryImageUploader.new
    File.open(file) do |f|
      uploader.store!(f)
    end
    uploader.url
  end

  def find_best_crop(width, height, file_path)

    if panoramic?
      center = width / 2
      center = find_center_of_objects(center, file_path, :x)
      crop_dimension = TARGET_WIDTH
      contrained_dimension = width
    else
      center = 0
      center = find_center_of_objects(center, file_path, :y)
      crop_dimension = target_height
      contrained_dimension = height
    end

    half_crop_dimension = crop_dimension / 2
    point = center - half_crop_dimension

    if point <= 0
      point = 0
    elsif center + half_crop_dimension > contrained_dimension
      point = contrained_dimension - crop_dimension
    end

    x = 0
    y = 0
    if panoramic?
      x = point
    else
      y = point
    end

    {x: x, y: y, width: TARGET_WIDTH.to_i, height: target_height.to_i}
  end

  def find_center_of_objects(center, file_path, dimension)
    detector = OpenCV::CvHaarClassifierCascade::load("#{Rails.root}/lib/assets/haarcascade_frontalface_alt.xml")
    image = OpenCV::CvMat.load(file_path)
    objects = detector.detect_objects(image)
    if objects.count > 0
      center = 0
      objects.each do |region|
        center += region.center.send(dimension)
      end
      center = center / objects.count.to_f
    end
    center
  end

end