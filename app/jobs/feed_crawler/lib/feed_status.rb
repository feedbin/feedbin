module FeedCrawler
  class FeedStatus
    def initialize(feed_id)
      @feed_id = feed_id
    end

    def self.clear!(*args)
      new(*args).clear!
    end

    def clear!
      Cache.delete(cache_key, errors_cache_key, log_cache_key)
    end

    def error!(exception, formatted: false)
      @count = count + 1
      Cache.write(cache_key, {
        count: @count,
        failed_at: Time.now.to_i
      })
      exception = formatted ? exception : error_json(exception)
      Sidekiq.redis do |redis|
        redis.pipelined do |pipeline|
          pipeline.lpush(errors_cache_key, exception)
          pipeline.ltrim(errors_cache_key, 0, 25)
        end
      end
    end

    def log_download!
      @downloaded_at = Time.now.to_i
      Cache.write(log_cache_key, {
        downloaded_at: @downloaded_at
      })
      @downloaded_at
    end

    def downloaded_at
      @downloaded_at ||= log_cache[:downloaded_at] && log_cache[:downloaded_at].to_i
    end

    def ok?
      Time.now.to_i > next_retry
    end

    def next_retry
      failed_at + backoff
    end

    def backoff
      multiplier = [count, 8].max
      multiplier = [multiplier, 23].min
      multiplier ** 4
    end

    def count
      @count ||= cached[:count].to_i
    end

    def failed_at
      cached[:failed_at].to_i
    end

    def attempt_log
      @attempt_log ||= begin
        Sidekiq.redis do |redis|
          redis.lrange(errors_cache_key, 0, -1)
        end.map do |json|
          data = JSON.load(json)
          data["date"] = Time.at(data["date"])
          data
        end
      end
    end

    def error_json(exception)
      status = exception.respond_to?(:response) ? exception.response.status.code : nil
      JSON.dump({date: Time.now.to_i, class: exception.class, message: exception.message, status: status})
    end

    def log_cache
      @log_cache ||= Cache.read(log_cache_key)
    end

    def cached
      @cached ||= Cache.read(cache_key)
    end

    def cache_key
      "refresher_status_#{@feed_id}"
    end

    def errors_cache_key
      "refresher_errors_#{@feed_id}"
    end

    def log_cache_key
      "refresher_log_#{@feed_id}"
    end
  end
end