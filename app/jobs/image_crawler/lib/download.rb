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

    # Feedkit rather than Down for block_ssrf, matching FeedCrawler::Downloader
    # and FeedFinder: every candidate url here comes out of feed content or a
    # publisher's markup, so it is attacker-chosen, and without this a crawl
    # can be aimed at the private network.
    #
    # Feedkit owns the conditional request too -- it builds If-None-Match and
    # If-Modified-Since from the validators below, and treats a 304 as success,
    # returning a bodiless Response instead of raising. That replaces a pair of
    # rescues that had to know which exception the configured Down backend used
    # to report a 304.
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

    # Empty for every caller that passes no validators (all of them outside
    # the icon family), and empty whenever this fetch is not actually for
    # @url: Download::Youtube/Vimeo/Instagram's #download override fetches a
    # *derived* URL (a thumbnail, an oEmbed target) while @etag/@last_modified
    # were computed for the original url passed to Download.new. Sending them
    # to the derived URL would risk a false 304 for a resource that was never
    # actually validated -- concretely, Vimeo's own url pattern matches
    # http://vimeo.com/favicon.ico, so a vimeo.com favicon crawl dispatches
    # into an oEmbed lookup whose thumbnail url is a different resource
    # entirely. `url` here is download_file's argument, compared against @url
    # *before* download_file's own camo substitution, so a camo-wrapped fetch
    # of the same logical resource still qualifies.
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

    # What the response carried, as opposed to what we sent. Stored against the
    # row so the next crawl of this same URL can ask conditionally. Feedkit
    # reads both case-insensitively, so the header spelling is its problem
    # rather than ours.
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