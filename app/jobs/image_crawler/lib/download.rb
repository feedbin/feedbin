module ImageCrawler
  class Download
    attr_reader :path

    def initialize(url, camo: false, minimum_size: 20_000)
      @url = url
      @valid = false
      @minimum_size = minimum_size
      @camo = camo
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
      @file = Down.download(url, max_size: 10 * 1024 * 1024, timeout_options: {read_timeout: 20, write_timeout: 5, connect_timeout: 5})
      @path = @file.path
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