module FeedCrawler
  class RedirectCache

    # 4 redirect/hr 24hrs a day for 6 days
    PERSIST_AFTER = 4 * 24 * 6

    attr_reader :redirects

    def initialize(feed_id)
      @feed_id = feed_id
    end

    def save(redirects)
      @redirects = redirects
      return unless redirect_stable?
      Cache.write(stable_key, {to: @redirects.last.to})
      @redirects.last.to
    end

    def redirect_stable?
      return false if @redirects.empty?
      return false unless @redirects.all?(&:permanent?)
      Cache.increment(counter_key, options: {expires_in: 72 * 60 * 60}) > PERSIST_AFTER
    end

    def read
      @read ||= Cache.read(stable_key)[:to]
    end

    def delete
      Cache.delete(stable_key)
    end

    def counter_key
      @counter_key ||= begin
        "refresher_redirect_tmp_" + Digest::SHA1.hexdigest(@redirects.map(&:cache_key).join)
      end
    end

    def stable_key
      @stable_key ||= begin
        "refresher_redirect_stable_#{@feed_id}"
      end
    end
  end
end
