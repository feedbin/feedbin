module FaviconCrawler
  class Processor
    attr_reader :host, :favicon_url, :encoded_favicon

    AWS_S3_BUCKET_FAVICONS = ENV["AWS_S3_BUCKET_FAVICONS"] || ENV["AWS_S3_BUCKET"]

    def initialize(favicon, host)
      @favicon = favicon
      @host = host
    end

    def favicon_hash
      @favicon_hash ||= Digest::SHA1.hexdigest(File.read(@favicon[:original]))
    end

    def call
      @favicon_url = upload
      @encoded_favicon = encoded
      self
    end

    private

    def upload
      File.open(@favicon[:resized]) do |file|
        response = Fog::Storage.new(STORAGE).put_object(AWS_S3_BUCKET_FAVICONS, File.join(favicon_hash[0..2], "#{favicon_hash}.png"), file, s3_options)
        URI::HTTPS.build(
          host: response.data[:host],
          path: response.data[:path]
        ).to_s
      end
    end

    def encoded
      Base64.encode64(File.read(@favicon[:resized])).delete("\n")
    end

    def s3_options
      {
        "Content-Type"            => "image/png",
        "Cache-Control"           => "max-age=315360000, public",
        "Expires"                 => "Sun, 29 Jun 2036 17:48:34 GMT",
        "x-amz-acl"               => "public-read",
        "x-amz-storage-class"     => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY",
        "x-amz-meta-favicon-host" => host
      }
    end
  end
end