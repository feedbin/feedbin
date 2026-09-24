module ImageCrawler
  # Remembers a candidate url that failed, so later crawls do not download
  # it again for a month. Only the url-addressed presets consult it: icons
  # always fetch (see Pipeline::Find#attempt_icon).
  class DownloadCache
    def initialize(url, image)
      @url = url
      @image = image
    end

    def download?
      !previously_attempted?
    end

    def previously_attempted?
      Cache.read(attempt_cache_key)[:attempted] == true
    end

    def failed!
      Cache.write(attempt_cache_key, {attempted: true}, options: {expires_in: 1.month})
    end

    def cache_key
      "image_download_#{@image.preset_name}_#{Digest::SHA1.hexdigest(@url)}_v4"
    end

    def attempt_cache_key
      "#{cache_key}_attempt"
    end
  end
end
