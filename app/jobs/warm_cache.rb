class WarmCache
  include Sidekiq::Worker

  SET_NAME = "#{name}-ids"

  def perform(feed_id, process = false)
    if process
      cache_changed_feeds
    else
      Sidekiq.redis { |redis| redis.sadd(SET_NAME, feed_id) }
    end
  end

  def cache_changed_feeds
    temporary_set = "#{self.class.name}-#{jid}"

    (_, _, feed_ids) = Sidekiq.redis do |redis|
      redis.pipelined do
        redis.renamenx(SET_NAME, temporary_set)
        redis.expire(temporary_set, 60)
        redis.smembers(temporary_set)
      end
    end

    Librato.increment "feeds_changed", by: feed_ids.length

    feed_ids.each do |feed_id|
      entries = Entry.where(feed_id: feed_id).order(published: :desc).limit(WillPaginate.per_page)
      ApplicationController.render partial: "entries/entry", collection: entries, cached: true
    end
  rescue Redis::CommandError => exception
    return logger.info("Nothing to do") if exception.message =~ /no such key/i
    raise
  end


end
