module ImageCrawler
  class MetaImagesCache
    FAILURE_THRESHOLD = 5
    FAILURE_EXPIRY = 24 * 60 * 60

    def initialize(url)
      @url = url
    end

    def urls
      url_cache[:urls]
    end

    def checked?
      !!url_cache[:checked]
    end

    def has_meta!(result)
      if result
        @host_cache = {has_meta: true}
        Cache.write(host_cache_key, @host_cache)
        Cache.delete(failure_count_key)
      else
        return if host_cache[:has_meta] == true

        failures = Cache.increment(failure_count_key, options: {expires_in: FAILURE_EXPIRY})
        if failures >= FAILURE_THRESHOLD
          @host_cache = {has_meta: false}
          Cache.write(host_cache_key, @host_cache, options: {expires_in: FAILURE_EXPIRY})
        end
      end
    end

    def has_meta?
      host_cache[:has_meta].nil? ? true : host_cache[:has_meta]
    end

    def save(data)
      @url_cache = data
      Cache.write(url_cache_key, data, options: {expires_in: 24 * 60 * 60})
    end

    def url_cache
      @url_cache ||= Cache.read(url_cache_key)
    end

    def host_cache
      @host_cache ||= Cache.read(host_cache_key)
    end

    def host_cache_key
      "image_host_v2_#{Digest::SHA1.hexdigest(@url.host)}"
    end

    def failure_count_key
      "image_host_failures_#{Digest::SHA1.hexdigest(@url.host)}"
    end

    def url_cache_key
      "image_url_#{Digest::SHA1.hexdigest(@url)}"
    end
  end
end