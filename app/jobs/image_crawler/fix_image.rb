module ImageCrawler
  class FixImage
    include Sidekiq::Worker
    sidekiq_options retry: false, queue: :utility

    POOL = ConnectionPool.new(size: 10) {
      HTTP.persistent("https://#{ImageCrawler::Image::BUCKET}.s3.amazonaws.com")
    }

    def perform(entry_id)
      entry = Entry.find(entry_id)
      processed_url = entry.image.safe_dig("processed_url")

      return unless processed_url

      if exists?(processed_url)
        Sidekiq.logger.info "Skipping, image exists public_id=#{entry.public_id} processed_url=#{processed_url}"
        return
      end

      entry.update(image: nil)

      return unless UnreadEntry.where(entry_id: entry.id).exists?

      Sidekiq.logger.info "Attempting to fix image public_id=#{entry.public_id} processed_url=#{processed_url}"

      ImageCrawler::EntryImage.perform_async(entry.public_id)
    end

    def exists?(url)
      url = URI.parse(url)
      POOL.with do |client|
        response = client.head(url.path).flush
        response.status.success?
      end
    end
  end
end
