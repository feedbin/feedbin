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

          if @image.content_addressed?
            break if attempt_icon(original_url)
          elsif @image.unified?
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

        if Dedupe.attach(original_url, @image)
          Librato.increment("image.dedupe_hit")
          Sidekiq.logger.info @image.trace(message: "attached existing image", metadata: {original_url: original_url})
          return true
        end

        # Only after the dedupe check: constructing a DownloadCache costs a
        # cache read, wasted on every dedupe hit.
        download_cache = DownloadCache.new(original_url, @image)
        if download_cache.download?
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

      # Icons mutate under a stable URL, so Dedupe's skip-the-download
      # shortcut is exactly wrong here. Always fetch -- conditionally when
      # possible -- then short-circuit on the original bytes, which skips
      # processing, the expensive part. Reached by every content_addressed?
      # preset.
      def attempt_icon(original_url)
        row = existing_row

        download = begin
          Download.download!(original_url,
            camo: @image.camo,
            minimum_size: @image.preset.minimum_size,
            **validators_for(row, original_url))
        rescue => exception
          Sidekiq.logger.info @image.trace(message: "download exception", metadata: {exception: exception, original_url: original_url})
          return false
        end

        return false unless download

        # Safe to trust: validators are stored per url (see validators_for),
        # so a 304 means this specific source is unchanged.
        if download.not_modified?
          Librato.increment("image.icon_not_modified")
          Sidekiq.logger.info @image.trace(message: "icon not modified", metadata: {original_url: original_url})
          return true
        end

        unless download.valid?
          download.delete!
          # No DownloadCache.failed!: icons always fetch, so undecodable
          # bytes are retried every crawl with no backoff -- deliberate.
          Sidekiq.logger.info @image.trace(message: "download invalid", metadata: {original_url: original_url})
          return false
        end

        @image.download_path        = download.persist!
        @image.final_url            = download.image_url
        @image.original_url         = original_url
        @image.original_extension   = download.file_extension
        @image.original_fingerprint = Digest::MD5.file(@image.download_path).hexdigest
        @image.etag                 = download.response_etag
        @image.last_modified        = download.response_last_modified

        if unchanged?(row)
          Librato.increment("image.icon_unchanged")
          Sidekiq.logger.info @image.trace(message: "icon unchanged", metadata: {original_url: original_url})
          store_validators(row, original_url)
          begin
            File.unlink(@image.download_path)
          rescue Errno::ENOENT
          end
          return true
        end

        Process.perform_async(@image.to_h)
        Sidekiq.logger.info @image.trace(message: "download valid", metadata: {image_url: @image.final_url})
        true
      end

      # Memoized with `defined?`, not `||=`, so a "no row yet" answer is
      # remembered instead of re-queried per candidate.
      def existing_row
        return @existing_row if defined?(@existing_row)
        @existing_row = ::Image.find_by(provider: @image.provider, provider_id: @image.provider_id.to_s)
      end

      # Only for the URL the row actually came from -- the restriction that
      # makes conditional requests trustworthy.
      def validators_for(row, original_url)
        return {} unless row && row.url == original_url
        {etag: row.etag, last_modified: row.last_modified}
      end

      # Unchanged bytes can still carry fresh validators (a rebuilt static
      # host re-etags identical content); store them so the next crawl can
      # 304. Guarded on row.url == original_url, mirroring validators_for: a
      # different candidate can serve byte-identical bytes, and writing its
      # validators under this row's url would let If-Modified-Since confirm a
      # false "unchanged" later. update_column, not update: updated_at is a
      # view cache key and must move only when the stored bytes move.
      def store_validators(row, original_url)
        return unless row && row.url == original_url
        merged = row.data.merge("etag" => @image.etag, "last_modified" => @image.last_modified).compact
        return if merged == row.data
        row.update_column(:data, merged)
      end

      # Image.same_fingerprint? is required: original_fingerprint reads back
      # dashed uuid, computed fingerprints are bare hex.
      def unchanged?(row)
        return false unless row
        return false unless row.variant == @image.variant
        ::Image.same_fingerprint?(row.original_fingerprint, @image.original_fingerprint)
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