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
        preset_name: "twitter",
        image_urls: [],
        provider: ::Image.providers[:entry_link],
        provider_id: @entry.id,
        entry_url: @page_url,
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    def receive
      @entry.data["twitter_link_image_processed"] = @image["processed_url"]
      @entry.data["twitter_link_image_placeholder_color"] = @image["placeholder_color"]
      @entry.save!
    end
  end
end