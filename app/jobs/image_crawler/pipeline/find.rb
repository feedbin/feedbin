module ImageCrawler
  module Pipeline
    class Find
      include Sidekiq::Worker
      sidekiq_options queue: :crawl_images, retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.image_urls = combine_urls(@image.image_urls, @image.entry_url)

        timer = Timer.new(45)
        count = 0

        while original_url = @image.image_urls.shift
          count += 1

          if count > 10
            Sidekiq.logger.info "Exceeded count limit: public_id=#{@image.id} count=#{count}"
            break
          end

          if timer.expired?
            Sidekiq.logger.info "Exceeded total time limit: public_id=#{@image.id} elapsed_time=#{timer.elapsed}"
            break
          end

          Sidekiq.logger.info "Candidate: public_id=#{@image.id} original_url=#{original_url} count=#{count}"

          download_cache = DownloadCache.copy(original_url, @image)

          if download_cache.copied?
            image             = download_cache.cached_image
            image.storage_url = download_cache.storage_url
            image.id          = @image.id
            image.provider    = @image.provider
            image.provider_id = @image.provider_id

            image.send_to_feedbin

            Sidekiq.logger.info "Copied image: public_id=#{image.id} image_url=#{image.final_url} storage_url=#{image.storage_url}"
            break
          elsif download_cache.download?
            break if download_image(original_url, download_cache)
          else
            Sidekiq.logger.info "Skipping download: public_id=#{@image.id} original_url=#{original_url}"
          end
        end
      end

      def download_image(original_url, download_cache)
        found = false

        download = begin
          Download.download!(original_url, camo: @image.camo, minimum_size: @image.preset.minimum_size)
        rescue => exception
          Sidekiq.logger.info "Download failed: exception=#{exception.inspect} original_url=#{original_url}"
          false
        end

        return unless download

        if download.valid?
          found = true

          @image.download_path      = download.persist!
          @image.final_url          = download.image_url
          @image.original_url       = original_url
          @image.original_extension = download.file_extension

          Process.perform_async(@image.to_h)
          Sidekiq.logger.info "Download valid: public_id=#{@image.id} image_url=#{@image.final_url}"
        else
          download.delete!
          download_cache.failed!
          Sidekiq.logger.info "Download invalid: public_id=#{@image.id} original_url=#{@image.original_url}"
        end
        found
      end

      def combine_urls(image_urls, entry_url)
        return image_urls unless entry_url

        page_urls = if Download.find_download_provider(entry_url)
          Sidekiq.logger.info "Recognized URL: entry_url=#{entry_url}"
          [entry_url]
        else
          Sidekiq.logger.info "MetaImages: count=#{page_urls&.length || 0} entry_url=#{entry_url}"
          MetaImages.find_urls(entry_url)
        end

        page_urls ||= []
        page_urls.concat(image_urls || [])
      end
    end
  end
end