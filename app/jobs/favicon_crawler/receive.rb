module FaviconCrawler
  class Receive
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(image_hash)
      @image = Image.new(image_hash)

      Icon.create!(provider: Icon.providers[@image.icon_provider], url: @image.final_url, provider_id: @image.favicon_host)

      fingerprint = RemoteFile.fingerprint(@image.final_url)
      RemoteFile.create!(
        fingerprint: fingerprint,
        original_url: @image.final_url,
        storage_url: @image.storage_url,
        width: @image.width,
        height: @image.height,
      )
    end
  end
end