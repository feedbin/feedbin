module FeedCrawler
  class Throttle

    TIMEOUT = 60 * 30

    def initialize(feed_url, last_download)
      @feed_url = feed_url
      @last_download = last_download
    end

    def self.throttled?(*args)
      new(*args).throttled?
    end

    def throttled?
      throttled_hosts.include?(host) && downloaded_recently?
    end

    def downloaded_recently?
      return false if @last_download.nil?
      (Time.now.to_i - @last_download) < random_timeout
    end

    def random_timeout
      rand(TIMEOUT..(TIMEOUT * 2))
    end

    def throttled_hosts
      ENV["THROTTLED_HOSTS"]&.split(",") || []
    end

    def host
      Addressable::URI.heuristic_parse(@feed_url).host.split(".").last(2).join(".")
    rescue
      nil
    end
  end
end