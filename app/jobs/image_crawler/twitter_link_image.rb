module ImageCrawler
  class TwitterLinkImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(public_id, image = nil, page_url = nil)
      public_id = public_id.split("-").first
      @entry = Entry.find_by_public_id(public_id)
      @image = image
      @page_url = page_url

      if @image
        receive
      else
        schedule
      end
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      image = Image.new_with_attributes(
        id: "#{@entry.public_id}-twitter",
        kind: ::Image.kinds[:poster],
        preset_name: "twitter",
        image_urls: [],
        provider: ::Image.providers[:entry_link_preview],
        provider_id: @entry.id,
        entry_url: @page_url,
        feed_id: @entry.feed_id,
        page_url: @page_url
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    def receive
      @image.fetch("storage_path")
      @entry.touch
    end
  end
end
