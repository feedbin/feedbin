module IconCrawler
  module Provider
    class Youtube
      include Sidekiq::Worker

      def perform(provider_id)
        provider = Icon.providers[:youtube]

        embed = Embed.youtube_channel.find_by(provider_id:)

        return if embed.nil?

        return if Icon.create_from_cache(url: embed.icon_url, provider:, provider_id:)

        image = ImageCrawler::Image.new(
          id: SecureRandom.hex,
          preset_name: "favicon",
          image_urls: [embed.icon_url],
          icon_provider_id: provider_id,
          icon_provider: provider
        )
        ImageCrawler::Pipeline::Find.perform_async(image.to_h)
      end
    end
  end
end