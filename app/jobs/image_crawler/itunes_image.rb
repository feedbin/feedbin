module ImageCrawler
  # An episode's own art, as an entry_icon row keyed by the entry. The
  # podcast preset has no callback: the entry list's cache key digests the
  # row, and no other cache holds episode art.
  class ItunesImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(public_id)
      if ENV["SKIP_IMAGES"].present?
        Rails.logger.info("SKIP_IMAGES is present, no images will be processed")
        return
      end

      entry = Entry.find_by_public_id!(public_id)
      image = Image.new_with_attributes(
        id: "#{entry.public_id}-itunes",
        kind: ::Image.kinds[:cover_art],
        preset_name: "podcast",
        image_urls: [entry.rebase_url(entry.data["itunes_image"])],
        provider: ::Image.providers[:entry_icon],
        provider_id: entry.id
      )
      Pipeline::Find.perform_async(image.to_h)
    rescue ActiveRecord::RecordNotFound
    end
  end
end
