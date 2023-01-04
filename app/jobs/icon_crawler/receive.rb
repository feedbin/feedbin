module FaviconCrawler
  class Receive
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(image_hash)
      @image = ImageCrawler::Image.new(image_hash)

      update = {
        provider_id: @image.icon_provider_id,
        provider: Icon.providers[@image.icon_provider],
        fingerprint: @image.fingerprint,
        url: @image.final_url
      }
      icon = Icon.create_with(update).find_or_create_by(provider_id: @image.icon_provider_id, provider: Icon.providers[@image.icon_provider])
      icon.update(update)

      fingerprint = RemoteFile.fingerprint(@image.final_url)
      update = {
        fingerprint: fingerprint,
        original_url: @image.final_url,
        storage_url: @image.storage_url,
        width: @image.width,
        height: @image.height,
      }
      file = RemoteFile.create_with(update).find_or_create_by(fingerprint: fingerprint)
      file.update(update)
    end
  end
end