class DownloadImage

  def initialize(url)
    @url = url
  end

  def file
    @file ||= begin
      file = nil
      options = {use_ssl: @url.scheme == "https", open_timeout: 5, read_timeout: 30}
      Net::HTTP.start(@url.host, @url.port, options) do |http|
        http.request_get(@url.request_uri) do |response|
          file = download_image(response) if headers_valid?(response.to_hash)
        end
      end
      file
    end
  end

  private

  def download_image(response)
    Pathname.new(File.join(Dir.tmpdir, "#{SecureRandom.hex}.jpg")).tap do |path|
      File.open(path, "wb") do |file|
        response.read_body do |chunk|
          file.write(chunk)
        end
      end
    end
  end

  def headers_valid?(headers)
    headers["content-type"].first == "image/jpeg" && headers["content-length"].first.to_i > 20_000
  rescue
    false
  end

end