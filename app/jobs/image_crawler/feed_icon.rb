module ImageCrawler
  # The feed-level icon for the sources the parser hands us as urls: the RSS
  # <image>, the JSON Feed icon, and the JSON Feed author avatar. Podcast art
  # has its own job (ItunesFeedImage) and outranks all of these, so a podcast
  # feed is declined here. The row is provider feed_icon keyed by the feed,
  # the same row the podcast job writes, so a feed has exactly one.
  class FeedIcon
    include Sidekiq::Worker
    sidekiq_options retry: false

    SUFFIX = "-icon".freeze

    def perform(feed_id, image = nil)
      feed_id = feed_id.to_s.split("-").first
      @feed = Feed.find(feed_id)
      @image = image

      if @image
        receive
      else
        self.class.schedule(@feed)
      end
    rescue ActiveRecord::RecordNotFound
    end

    # Returns whether a job was enqueued; BackfillFeedIcons counts on that.
    #
    # critical: a subscribe or a feed create is live and runs on the critical
    # queues. The backfill passes false, so its icons run behind live images.
    #
    # Kind is set here, at the call site, per source: only this job knows
    # which parser field a url came from.
    def self.schedule(feed, critical: true)
      return false if feed.options&.safe_dig("itunes_image").present?

      url, kind = source_for(feed)
      return false if url.nil?

      url = feed.feed_relative_url(url)
      # The legacy object second: Find tries candidates in order, so a dead
      # source still lands as a copy of what the proxy cached.
      candidates = [url, RemoteFile.legacy_object_url(url)].compact
      image = Image.new_with_attributes(
        id: "#{feed.id}-#{Digest::SHA1.hexdigest(url)}#{SUFFIX}",
        kind: ::Image.kinds[kind],
        preset_name: "feed_icon",
        image_urls: candidates,
        provider: ::Image.providers[:feed_icon],
        provider_id: feed.id,
        critical: critical
      )
      Pipeline::Find.perform_async(image.to_h)
      true
    end

    # Today's ranking, unchanged. The RSS image counts only for a micropost
    # feed, where it is the author's picture; for an article feed it is a
    # banner as often as a logo, and it stays ignored.
    def self.source_for(feed)
      options = feed.options || {}

      if (url = options.safe_dig("image", "url").presence) && feed.micropost?
        return [url, :avatar]
      end
      if (url = options.safe_dig("json_feed", "icon").presence)
        return [url, :site_icon]
      end
      if (url = options.safe_dig("json_feed", "author", "avatar").presence)
        return [url, :avatar]
      end

      nil
    end

    # Row-backed: the row is the read path. The touch moves the cached
    # sidebar and entry keys, because new bytes can land under the same path.
    def receive
      @image.fetch("storage_path")
      @feed.touch
    end
  end
end
