module ImageCrawler
  class ItunesFeedImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(feed_id, image = nil)
      feed_id = feed_id.to_s.split("-").first
      @feed = Feed.find(feed_id)
      @image = image

      if @image
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
          preset_name: "podcast_feed",
          image_urls: [url],
          provider: ::Image.providers[:avatar_url],
          provider_id: @feed.id
        )
        Pipeline::Find.perform_async(image.to_h)
      end
    end

    def receive
      @feed.update(custom_icon: @image["processed_url"], custom_icon_format: "square")
    end
  end
end