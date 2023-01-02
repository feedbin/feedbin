module FaviconCrawler
  class Receive
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(image_hash)
      @image = ImageCrawler::Image.new(image_hash)

      icon = Icon.create_with(
        provider_id: @image.favicon_host,
        provider: Icon.providers[@image.icon_provider],
        url: @image.final_url,
      ).find_or_create_by(provider_id: @image.favicon_host, provider: Icon.providers[@image.icon_provider])
      icon.update(url: @image.final_url)

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