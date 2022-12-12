module FeedCrawler
  class TwitterDownloader
    include Sidekiq::Worker
    sidekiq_options queue: :twitter, retry: false

    def perform(feed_id, feed_url, keys)
      feed = nil

      recognized_url = Feedkit::TwitterURLRecognizer.new(feed_url, nil)

      if recognized_url.valid?
        keys.find do |key|
          feed = Feedkit::Tweets.new(recognized_url, key["twitter_access_token"], key["twitter_access_secret"]).feed
        rescue Twitter::Error::TooManyRequests => error
          Sidekiq.logger.info "Twitter::Error::TooManyRequests twitter_url=#{feed_url} key=#{key["twitter_access_token"]} limit=#{error.rate_limit.limit} remaining=#{error.rate_limit.remaining} reset_at=#{error.rate_limit.reset_at} reset_in=#{error.rate_limit.reset_in}"
        rescue Twitter::Error::Unauthorized, Twitter::Error::Forbidden, Twitter::Error::NotFound, Twitter::Error::InternalServerError, Twitter::Error::ServiceUnavailable => error
          Sidekiq.logger.info "Twitter::Error twitter_url=#{feed_url} exception=#{error.inspect}"
        rescue HTTP::TimeoutError, HTTP::ConnectionError
          Sidekiq.logger.info "HTTP Error twitter_url=#{feed_url}"
        end
      end

      if feed
        entries = EntryFilter.filter!(feed.entries, check_for_changes: false, date_filter: (Date.today - 2).to_time)
        return if entries.empty?
        Receiver.perform_async({
          feed: {
            id: feed_id,
            options: feed.options
          },
          entries: entries
        })
      end
    end
  end
end