require 'rmagick'

class ProcessedImage

  MIN_WIDTH = 542
  WIDTH_RATIO = 16.to_f
  HEIGHT_RATIO = 9.to_f

  attr_reader :file_path

  def initialize(url)
    @url = url
    @valid = false
  end

  def valid?
    @valid
  end

  def process
    file = Tempfile.new('image')
    file.binmode
    begin
      if download(file) && image_valid?(file.path)
        puts "valid"
      else
        puts "not valid"
      end
    ensure
      # file.close
      # file.unlink
    end
    puts file.path.inspect
  end

  def download(file)
    success = false
    options = {use_ssl: @url.scheme == "https"}
    Net::HTTP.start(@url.host, @url.port, options) do |http|
      http.request_get(@url.path) do |response|
        if headers_valid?(response.to_hash)
          response.read_body do |chunk|
            file.write(chunk)
          end
          success = true
        end
      end
    end
    file.close
    success
  end

  def headers_valid?(headers)
    begin
      headers["content-type"].first == "image/jpeg" && headers["content-length"].first.to_i > 20_000
    rescue
      false
    end
  end

  def image_valid?(file)
    image = Magick::Image.ping(file).first
    width = image.columns.to_f
    height = image.rows.to_f
    image_ratio = height / width
    target_ratio = HEIGHT_RATIO / WIDTH_RATIO
    width > MIN_WIDTH && image_ratio <= 1 && image_ratio >= target_ratio
  end

end