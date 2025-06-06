module FeedCrawler
  class Throttle

    TIMEOUT = 60 * 30

    def initialize(feed_url)
      @feed_url = feed_url
    end

    def self.retry_after(...)
      new(...).retry_after
    end

    def retry_after
      return nil unless throttled_hosts.include?(host)
      Time.now.to_i + random_timeout
    end

    def random_timeout
      base = TIMEOUT * weight
      rand(base..(base * 2))
    end

    def throttled_hosts
      FeedbinUtils.key_value_parser(ENV["THROTTLED_HOSTS"]) do |weight|
        weight&.to_i || 1
      end
    end

    def weight
      throttled_hosts[host] || 1
    end

    def host
      Addressable::URI.heuristic_parse(@feed_url).host.split(".").last(2).join(".")
    rescue
      nil
    end
  end
end