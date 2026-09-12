module ImageCrawler
  class ItunesImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(public_id, image = nil)
      if ENV["SKIP_IMAGES"].present?
        Rails.logger.info("SKIP_IMAGES is present, no images will be processed")
        return
      end

      public_id = public_id.split("-").first
      @entry = Entry.find_by_public_id(public_id)
      @image = image

      if @image
        receive
      else
        schedule
      end
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      image = Image.new_with_attributes(
        id: "#{@entry.public_id}-itunes",
        kind: ::Image.kinds[:cover_art],
        preset_name: "podcast",
        image_urls: [@entry.rebase_url(@entry.data["itunes_image"])],
        provider: ::Image.providers[:entry_icon],
        provider_id: @entry.id
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    # Row-backed only. No touch needed: nothing renders episode artwork
    # through a cache keyed on this entry.
    def receive
      @image.fetch("storage_path")
      @entry.update(provider: Entry.providers[:entry_icon], provider_id: @entry.id)
    end
  end
end