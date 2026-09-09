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

    # Feedkit rather than Down for block_ssrf: candidate urls come out of
    # publisher content, so they are attacker-chosen. Feedkit also owns the
    # conditional request, treating a 304 as a bodiless success Response.
    def download_file(url)
      requested_url = url
      url = @camo ? RemoteFile.camo_url(url) : url
      @response = Feedkit::Request.download(url, block_ssrf: true, **validators_for(requested_url))

      if @response.status.code == 304
        # Gated on conditional?: a 304 nobody asked for is a broken server, not
        # a fresh image. Leaving @path nil makes the candidate read as invalid
        # rather than as unchanged, so a dead icon cannot look permanently
        # fresh and never be re-fetched.
        @not_modified = conditional?
      else
        @path = @response.path
      end
    end

    # Empty when no validators were passed, and empty when the fetch is for
    # a *derived* URL (Youtube/Vimeo/Instagram overrides fetch a thumbnail or
    # oEmbed target): the validators were computed for @url, and sending them
    # elsewhere risks a false 304 for a never-validated resource. Compared
    # before camo substitution, so a camo-wrapped fetch still qualifies.
    def validators_for(url)
      return {} unless url == @url
      {etag: @etag, last_modified: @last_modified}
    end

    def conditional?
      @etag.present? || @last_modified.present?
    end

    def not_modified?
      @not_modified
    end

    # What the response carried, stored so the next crawl of this URL can
    # ask conditionally.
    def response_etag
      @response&.etag
    end

    def response_last_modified
      @response&.last_modified
    end

    def persist!
      unless @path == persisted_path
        FileUtils.mv @path, persisted_path
        @path = persisted_path
      end
      persisted_path
    end

    def delete!
      @path && File.unlink(@path)
    rescue Errno::ENOENT
    end

    def persisted_path
      @persisted_path ||= File.join(Dir.tmpdir, ["image_original_", SecureRandom.hex, ".#{file_extension}"].join)
    end

    def file_extension
      content_type = @response&.headers&.[]("Content-Type")

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
      return false if @path.nil?
      return true if @minimum_size.nil?
      File.size(@path) >= @minimum_size
    end

    def provider_identifier
      self.class.recognize_url?(@url)
    end

    def self.recognize_url?(src_url)
      if supported_urls.find { src_url.to_s =~ it }
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