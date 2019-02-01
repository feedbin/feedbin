class FaviconProcessor
  attr_reader :data, :host

  def initialize(data, host)
    @data = data
    @host = host
  end

  def favicon_url
    @favicon_url ||= upload(image_data)
  end

  def encoded_favicon
    @encoded_favicon ||= encoded(image_data)
  end

  def valid?
    data.present?
  end

  def favicon_hash
    @favicon_hash ||= Digest::SHA1.hexdigest(data)
  end

  def upload_existing
    upload(data)
  end

  private

  def upload(data)
    upload_url = nil
    S3_POOL.with do |connection|
      response = connection.put_object(ENV["AWS_S3_BUCKET_FAVICONS"], File.join(favicon_hash[0..2], "#{favicon_hash}.png"), data, s3_options)
      upload_url = URI::HTTP.build(
        scheme: "https",
        host: response.data[:host],
        path: response.data[:path],
      ).to_s
    end
    upload_url
  end

  def encoded(blob)
    Base64.encode64(blob).delete("\n")
  end

  def image_data
    @image_data ||= get_image_data
  end

  def get_image_data
    layers = load_layers
    favicon = remove_blank_images(layers).last
    if favicon.columns > 32
      favicon = favicon.resize_to_fit(32, 32)
    end
    favicon.to_blob { |image| image.format = "png" }
  ensure
    favicon&.destroy!
    layers&.map(&:destroy!)
  end

  def load_layers
    Magick::Image.from_blob(data)
  rescue Magick::ImageMagickError
    Magick::Image.from_blob(data) { |image| image.format = "ico" }
  end

  def remove_blank_images(layers)
    layers.reject do |layer|
      layer = layer.scale(1, 1)
      pixel = layer.pixel_color(0, 0)
      color = layer.to_color(pixel)
      %w[none white].include?(color) || color.include?("#FFFFFF")
    end
  end

  def s3_options
    {
      "Content-Type" => "image/png",
      "Cache-Control" => "max-age=315360000, public",
      "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
      "x-amz-acl" => "public-read",
      "x-amz-storage-class" => "REDUCED_REDUNDANCY",
      "x-amz-meta-favicon-host" => host,
    }
  end

  def path
    @path ||= File.join("public-favicons", favicon_hash[0..3], "#{favicon_hash}.png")
  end
end
