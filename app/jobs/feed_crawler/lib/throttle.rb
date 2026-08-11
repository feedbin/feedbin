module FeedCrawler
  class Throttle

    TIMEOUT = 60 * 30

    HOST = %r{\A[a-z][a-z0-9+\-.]*://(?:[^/?#]*@)?([^/?#:]+)}i

    def initialize(feed_url)
      @feed_url = feed_url
    end

    def self.retry_after(...)
      new(...).retry_after
    end

    def self.throttled_hosts
      value = ENV["THROTTLED_HOSTS"]
      return @throttled_hosts if @throttled_hosts && @throttled_hosts_source == value
      @throttled_hosts_source = value
      @throttled_hosts = FeedbinUtils.key_value_parser(value) do |weight|
        weight&.to_i || 1
      end
    end

    def retry_after
      return nil if throttled_hosts.empty?
      return nil unless throttled_hosts.include?(host)
      Time.now.to_i + random_timeout
    end

    def random_timeout
      base = TIMEOUT * weight
      rand(base..(base * 2))
    end

    def throttled_hosts
      self.class.throttled_hosts
    end

    def weight
      throttled_hosts[host] || 1
    end

    def host
      return @host if defined?(@host)
      @host = @feed_url.to_s[HOST, 1]&.split(".")&.last(2)&.join(".")
    end
  end
end
