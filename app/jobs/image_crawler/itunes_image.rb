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
      # No touch. The legacy storage key comes from image_name, which is built
      # from the job id ("<public_id>-itunes") and is therefore stable no
      # matter what the bytes are -- new artwork overwrites the same key and
      # yields the same processed_url, so the update above genuinely no-ops
      # on a bytes-only change. But nothing renders episode artwork through a
      # cache keyed on this entry, so there is no staleness for a touch to
      # fix: EntryPresenter#media_image is read only by entries/_media and
      # entries/_audio_markup, and neither sits inside a cache block --
      # entries_controller#show renders inner_content fresh on every request.
      # The one cache keyed on this entry, entries/_entry (EntriesHelper.
      # entries_cache_key), never calls media_image at all. The podcast API
      # views expose the raw source itunes_image url, not the processed one,
      # so they have nothing to invalidate either.
      @entry.update(
        media_image: @image["processed_url"],
        provider: Entry.providers[:entry_icon],
        provider_id: @entry.id
      )
    end
  end
end