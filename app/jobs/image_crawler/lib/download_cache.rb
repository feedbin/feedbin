module ImageCrawler
  class DownloadCache

    attr_reader :storage_url, :cached_image

    def initialize(url, image)
      @url = url
      @image = image
      @cached_image = from_cache
    end

    def from_cache
      data = Cache.read(cache_key)
      data.present? ? Image.new(data) : nil
    end

    def self.copy(*args)
      instance = new(*args)
      instance.copy
      instance
    end

    def self.save(image)
      new(image.original_url, image).save(image)
    end

    def copy
      copy_image unless @cached_image.nil?
    end

    def copied?
      !!@storage_url
    end

    def download?
      !previously_attempted?
    end

    def save(image)
      Cache.write(cache_key, image.to_h, options: {expires_in: 1.week})
    end

    def previously_attempted?
      Cache.read(attempt_cache_key)[:attempted] == true
    end

    def failed!
      Cache.write(attempt_cache_key, {attempted: true}, options: {expires_in: 1.month})
    end

    def cache_key
      "image_download_#{@image.preset_name}_#{Digest::SHA1.hexdigest(@url)}_v3"
    end

    def attempt_cache_key
      "#{cache_key}_attempt"
    end

    def copy_image
      url = URI.parse(@cached_image.storage_url)
      source_object_name = url.path[1..-1]
      copied_image_name = "#{@image.image_name}#{@cached_image.processed_extension}"
      Fog::Storage.new(STORAGE).copy_object(@cached_image.bucket, source_object_name, @cached_image.bucket, copied_image_name, @cached_image.storage_options)
      url.path = "/#{copied_image_name}"
      @storage_url = url.to_s
    rescue Excon::Error::NotFound
      false
    end
  end
end
