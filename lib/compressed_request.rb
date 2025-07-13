require "zlib"

class CompressedRequest
  MAX_DECOMPRESSED_SIZE = 10 * 1024 * 1024 # 10MB
  CHUNK_SIZE = 64 * 1024 # 64KB

  def initialize(app)
    @app = app
  end

  def call(env)
    if extension?(env) && gzipped?(env)
      decompress_body!(env)
    end
    @app.call(env)
  end

  private

  def extension?(env)
    env["REQUEST_PATH"].start_with?("/extension/v1/pages")
  end

  def gzipped?(env)
    env["HTTP_CONTENT_ENCODING"] == "gzip"
  end

  def decompress_body!(env)
    compressed_body = env["rack.input"].read
    env["rack.input"].rewind if env["rack.input"].respond_to?(:rewind)

    begin
      decompressed_body = stream_decompress(compressed_body)
      env["rack.input"] = StringIO.new(decompressed_body)
      env["CONTENT_LENGTH"] = decompressed_body.bytesize.to_s
      env.delete("HTTP_CONTENT_ENCODING")
    rescue Zlib::GzipFile::Error, Zlib::Error => exception
      env["rack.input"] = StringIO.new(compressed_body)
      Rails.logger.warn "Failed to decompress gzipped request: #{exception.message}"
    rescue StandardError => exception
      env["rack.input"] = StringIO.new(compressed_body)
      Rails.logger.error "Gzip decompression error: #{exception.message}"
      raise
    end
  end

  def stream_decompress(compressed_data)
    decompressed = StringIO.new
    decompressed_size = 0

    Zlib::GzipReader.wrap(StringIO.new(compressed_data)) do |reader|
      while chunk = reader.read(CHUNK_SIZE)
        decompressed_size += chunk.bytesize
        if decompressed_size > MAX_DECOMPRESSED_SIZE
          raise StandardError, "Decompressed size exceeds maximum allowed (#{MAX_DECOMPRESSED_SIZE} bytes)"
        end
        decompressed.write(chunk)
      end
    end

    decompressed.string
  end
end