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
        preset_name: "podcast",
        image_urls: [@entry.rebase_url(@entry.data["itunes_image"])],
        provider: ::Image.providers[:entry_icon],
        provider_id: @entry.id
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    def receive
      # media_image stays written either way: it is still the fallback read
      # path until the legacy store retires, and one write per episode is not
      # a fan-out worth avoiding.
      #
      # The touch is not redundant with that update. The legacy S3 key comes
      # from image_name, which is built from the job id ("<public_id>-itunes")
      # and is therefore stable no matter what the bytes are -- new artwork
      # overwrites the same key and yields the same processed_url, so the
      # update no-ops and bumps nothing. Without the touch, artwork that
      # changed would leave every cached view keyed on this entry stale.
      @entry.update(
        media_image: @image["processed_url"],
        provider: Entry.providers[:entry_icon],
        provider_id: @entry.id
      )
      @entry.touch if @image["storage_path"]
    end
  end
end