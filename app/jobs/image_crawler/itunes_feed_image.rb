module ImageCrawler
  class ItunesFeedImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(feed_id, image = nil)
      feed_id = feed_id.to_s.split("-").first
      @feed = Feed.find(feed_id)

      if image
        receive
      else
        schedule
      end
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      if url = @feed.options&.safe_dig("itunes_image")
        name = Digest::SHA1.hexdigest(url)
        url = @feed.site_relative_url(url)

        image = Image.new_with_attributes(
          id: "#{@feed.id}-#{name}-itunes",
          kind: ::Image.kinds[:cover_art],
          preset_name: "podcast_feed",
          image_urls: [url],
          provider: ::Image.providers[:feed_icon],
          provider_id: @feed.id
        )
        Pipeline::Find.perform_async(image.to_h)
      end
    end

    # The row is the read path and its kind is the shape. The touch moves
    # the cached views, because new artwork can land under the same path.
    def receive
      @feed.touch
    end
  end
end