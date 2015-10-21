require 'rmagick'
require 'opencv'

class DownloadImage

  attr_reader :image, :url

  def initialize(url)
    @url = url
    @image = nil
  end

  def download
    success = false
    if @image = get_image
      success = @image.process
    end
    success
  end

  def get_image
    file = Tempfile.new('image')
    file.binmode
    image = nil
    options = {
      use_ssl: @url.scheme == "https",
      open_timeout: 5,
      read_timeout: 30,
    }
    Net::HTTP.start(@url.host, @url.port, options) do |http|
      http.request_get(@url.request_uri) do |response|
        if headers_valid?(response.to_hash)
          response.read_body do |chunk|
            file.write(chunk)
          end
          file.rewind
          file.close
          image = ProcessedImage.new(file)
        else
          file.close(true)
        end
      end
    end
    image
  end

  def headers_valid?(headers)
    begin
      headers["content-type"].first == "image/jpeg" && headers["content-length"].first.to_i > 20_000
    rescue
      false
    end
  end

end