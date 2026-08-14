module ImageCrawler
  class Download
    attr_reader :path

    def initialize(url, camo: false, minimum_size: 20_000, etag: nil, last_modified: nil)
      @url = url
      @valid = false
      @minimum_size = minimum_size
      @camo = camo
      @etag = etag
      @last_modified = last_modified
      @not_modified = false
    end

    def self.download!(url, **args)
      klass = find_download_provider(url) || Download::Default
      instance = klass.new(url, **args)
      instance.download
      instance
    end

    def image_url
      @url
    end

    def download_file(url)
      url = @camo ? RemoteFile.camo_url(url) : url
      @file = Down.download(url, max_size: 10 * 1024 * 1024, headers: conditional_headers, timeout_options: {read_timeout: 20, write_timeout: 5, connect_timeout: 5})
      @path = @file.path
    rescue Down::ResponseError => exception
      # A 304 is the success case for a conditional request, not an error: the
      # server is confirming the bytes we already hold are current. Down has no
      # other way to say it -- it raises on every non-2xx. Narrow on purpose:
      # a 404 or a 500 must stay an error, or a dead icon would look
      # permanently unchanged and never be re-fetched. Also gated on having
      # sent a validator: a 304 nobody asked for is a broken server, not a
      # fresh icon, and must not be treated as "unchanged".
      raise unless (@etag.present? || @last_modified.present?) && exception.response&.code.to_s == "304"
      @not_modified = true
    end

    # Empty for every caller that passes no validators, which is all of them
    # outside the icon family.
    def conditional_headers
      {}.tap do |headers|
        headers["If-None-Match"]     = @etag          if @etag.present?
        headers["If-Modified-Since"] = @last_modified if @last_modified.present?
      end
    end

    def not_modified?
      @not_modified
    end

    # What the response carried, as opposed to what we sent. Stored against the
    # row so the next crawl of this same URL can ask conditionally.
    #
    # "Etag", not "ETag": the configured :http backend (see config/initializers/down.rb)
    # canonicalizes header names to Title-Case-Per-Hyphen-Segment, and "ETag" has no
    # hyphen to break on, so it comes back as "Etag". Verified directly against the
    # installed gems -- "Content-Type" and "Last-Modified" both happen to already be
    # hyphenated the same way the backend canonicalizes them, which is why file_extension's
    # existing "Content-Type" lookup works without needing this note.
    def response_etag
      @file&.headers&.[]("Etag")
    end

    def response_last_modified
      @file&.headers&.[]("Last-Modified")
    end

    def persist!
      unless @path == persisted_path
        FileUtils.mv @path, persisted_path
        @path = persisted_path
      end
      persisted_path
    end

    def delete!
      @file.respond_to?(:close) && @file.close
      @file.respond_to?(:unlink) && @file.unlink
      @path && File.unlink(@path)
    rescue Errno::ENOENT
    end

    def persisted_path
      @persisted_path ||= File.join(Dir.tmpdir, ["image_original_", SecureRandom.hex, ".#{file_extension}"].join)
    end

    def file_extension
      content_type = @file.headers["Content-Type"]

      return unless content_type.respond_to?(:start_with?)

      if content_type.start_with?("image/png")
        "png"
      elsif content_type.start_with?("image/jpg") || content_type.start_with?("image/jpeg")
        "jpg"
      else
        "unknown"
      end
    end

    def valid?
      return false if @file.nil?
      return true if @minimum_size.nil?
      @file.size >= @minimum_size
    end

    def provider_identifier
      self.class.recognize_url?(@url)
    end

    def self.recognize_url?(src_url)
      if supported_urls.find { src_url.to_s =~ _1 }
        Regexp.last_match[1]
      else
        false
      end
    end

    def self.find_download_provider(url)
      download_providers.detect { |klass| klass.recognize_url?(url) }
    end

    def self.download_providers
      [
        Download::Youtube,
        Download::Instagram,
        Download::Vimeo
      ]
    end

    def self.supported_urls
      []
    end
  end
end