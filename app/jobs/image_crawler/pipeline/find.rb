module ImageCrawler
  module Pipeline
    class Find
      include Sidekiq::Worker
      sidekiq_options queue: :crawl_images, retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.image_urls = combine_urls(@image.image_urls, @image.entry_url)

        Sidekiq.logger.info @image.trace(message: "starting")

        timer = Timer.new(45)
        count = 0

        if @image.image_urls.empty?
          Sidekiq.logger.info @image.trace(message: "no image candidates found, skipping")
        end

        while original_url = @image.image_urls.shift
          count += 1

          if count > 10
            Sidekiq.logger.info @image.trace(message: "exceeded count limit", metadata: {count: count})
            break
          end

          if timer.expired?
            Sidekiq.logger.info @image.trace(message: "exceeded total time limit", metadata: {elapsed_time: timer.elapsed})
            break
          end

          Sidekiq.logger.info @image.trace(message: "attempting image candidate", metadata: {original_url: original_url})

          if @image.unified?
            break if attempt_unified(original_url)
          else
            break if attempt_legacy(original_url)
          end
        end
      rescue => exception
        Sidekiq.logger.info @image.trace(message: "find image exception", metadata: {exception: exception, backtrace: exception.backtrace})
      end

      def attempt_unified(original_url)
        if reuse_rules.skip?(original_url)
          Librato.increment("image.reuse_skipped")
          Sidekiq.logger.info @image.trace(message: "skipping reused image", metadata: {original_url: original_url})
          return false
        end

        download_cache = DownloadCache.new(original_url, @image)

        if Dedupe.attach(original_url, @image)
          Librato.increment("image.dedupe_hit")
          Sidekiq.logger.info @image.trace(message: "attached existing image", metadata: {original_url: original_url})
          true
        elsif download_cache.download?
          download_image(original_url, download_cache)
        else
          Sidekiq.logger.info @image.trace(message: "skipping image", metadata: {original_url: original_url})
          false
        end
      end

      def attempt_legacy(original_url)
        download_cache = DownloadCache.copy(original_url, @image)

        if download_cache.copied?
          image             = download_cache.cached_image
          image.storage_url = download_cache.storage_url
          image.id          = @image.id
          image.provider    = @image.provider
          image.provider_id = @image.provider_id

          image.send_to_feedbin

          Sidekiq.logger.info @image.trace(message: "copied existing image", metadata: {image_url: @image.final_url, storage_url: @image.storage_url})
          true
        elsif download_cache.download?
          download_image(original_url, download_cache)
        else
          Sidekiq.logger.info @image.trace(message: "skipping image", metadata: {image_url: @image.final_url})
          false
        end
      end

      def download_image(original_url, download_cache)
        found = false

        download = begin
          Download.download!(original_url, camo: @image.camo, minimum_size: @image.preset.minimum_size)
        rescue => exception
          Sidekiq.logger.info @image.trace(message: "download exception", metadata: {exception: exception, original_url: original_url})
          false
        end

        return unless download

        if download.valid?
          found = true

          @image.download_path      = download.persist!
          @image.final_url          = download.image_url
          @image.original_url       = original_url
          @image.original_extension = download.file_extension
          # Digest::MD5.file streams the file through the digest in C; the
          # File.read form would allocate the whole image as a Ruby string.
          @image.original_fingerprint = Digest::MD5.file(@image.download_path).hexdigest

          Process.perform_async(@image.to_h)
          Sidekiq.logger.info @image.trace(message: "download valid", metadata: {image_url: @image.final_url})
        else
          download.delete!
          download_cache.failed!
          Sidekiq.logger.info @image.trace(message: "download invalid", metadata: {original_url: @image.original_url})
        end
        found
      end

      def combine_urls(image_urls, entry_url)
        return image_urls unless entry_url

        page_urls = if Download.find_download_provider(entry_url)
          Sidekiq.logger.info "Recognized URL: entry_url=#{entry_url}"
          [entry_url]
        else
          found = MetaImages.find_urls(entry_url).map(&:to_s)
          Sidekiq.logger.info "MetaImages: count=#{found.length} entry_url=#{entry_url}"
          @image.meta_image_urls = (@image.meta_image_urls || []) | found
          found
        end

        page_urls ||= []
        page_urls.concat(image_urls || [])
      end

      def reuse_rules
        @reuse_rules ||= ReuseRules.new(@image)
      end
    end
  end
end