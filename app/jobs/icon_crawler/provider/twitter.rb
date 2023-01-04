module IconCrawler
  module Provider
    class Twitter
      include Sidekiq::Worker
      sidekiq_options retry: false

      def perform(provider_id, url)
        provider = Icon.providers[:twitter]

        return if Icon.create_from_cache(url:, provider:, provider_id:)

        image = ImageCrawler::Image.new(
          id: SecureRandom.hex,
          preset_name: "favicon",
          image_urls: [url],
          icon_provider_id: provider_id,
          icon_provider: provider
        )
        ImageCrawler::Pipeline::Find.perform_async(image.to_h)
      end
    end
  end
end