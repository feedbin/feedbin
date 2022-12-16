module ImageCrawler
  class DownloadCache
    include ImageCrawlerHelper

    attr_reader :storage_url

    def initialize(url, public_id:, preset_name:)
      @url = url
      @public_id = public_id
      @preset_name = preset_name
      @storage_url = nil
    end

    def self.copy(url, **args)
      instance = new(url, **args)
      instance.copy
      instance
    end

    def copy
      @storage_url = copy_image unless storage_url.nil? || storage_url == false
    end

    def copied?
      !!@storage_url
    end

    def storage_url
      @storage_url ||= cache[:storage_url]
    end

    def image_url
      @image_url ||= cache[:image_url]
    end

    def placeholder_color
      @placeholder_color ||= cache[:placeholder_color]
    end

    def download?
      !previously_attempted? && storage_url != false
    end

    def previously_attempted?
      !cache.empty?
    end

    def save(storage_url:, image_url:, placeholder_color:)
      @cache = {storage_url:, image_url:, placeholder_color:}
      Cache.write(cache_key, @cache, options: {expires_in: 7 * 24 * 60 * 60})
    end

    def cache
      @cache ||= Cache.read(cache_key)
    end

    def cache_key
      "image_download_#{@preset_name}_#{Digest::SHA1.hexdigest(@url)}"
    end

    def copy_image
      url = URI.parse(storage_url)
      source_object_name = url.path[1..-1]
      Fog::Storage.new(STORAGE).copy_object(bucket, source_object_name, bucket, image_name, storage_options)
      final_url = url.path = "/#{image_name}"
      url.to_s
    rescue Excon::Error::NotFound
      false
    end
  end
end
