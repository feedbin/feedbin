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
          provider: ::Image.providers[:feed_icon],
          provider_id: @feed.id
        )
        Pipeline::Find.perform_async(image.to_h)
      end
    end

    def receive
      # custom_icon stays written either way: it is still the fallback read
      # path until the legacy store retires, and it is what icon_options reads
      # to decide the icon's shape.
      #
      # The touch is not redundant with that update. The legacy storage key comes
      # from image_name, built from the job id, whose only variable part is a
      # digest of the *source url* -- so a show that replaces its artwork at
      # the same url overwrites the same key, yields the same processed_url,
      # and the update no-ops. Without the touch, the sidebar and every entry
      # summary for this feed would keep serving the old artwork.
      @feed.update(custom_icon: @image["processed_url"], custom_icon_format: "square")
      @feed.touch if @image["storage_path"]
    end
  end
end