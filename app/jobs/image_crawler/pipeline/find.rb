module ImageCrawler
  module Pipeline
    class Find
      include Sidekiq::Worker
      sidekiq_options queue: :crawl_images, retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)

        # A development box without a bucket has nowhere to write. Production
        # does not boot without one (Image.check_storage_config!).
        unless ::Image.storage_configured?
          @image.trace(message: "no image store configured, skipping")
          return
        end

        @image.image_urls = combine_urls(@image.image_urls, @image.entry_url)
        @image.trace(message: "starting")

        timer = Timer.new(45)
        count = 0

        if @image.image_urls.empty?
          @image.trace(message: "no image candidates found, skipping")
        end

        while (original_url = @image.image_urls.shift)
          count += 1

          if count > 10
            @image.trace(message: "exceeded count limit", metadata: {count: count})
            break
          end

          if timer.expired?
            @image.trace(message: "exceeded total time limit", metadata: {elapsed_time: timer.elapsed})
            break
          end

          @image.trace(message: "attempting image candidate", metadata: {original_url: original_url})

          if @image.content_addressed?
            break if attempt_content_addressed(original_url)
          else
            break if attempt_url_addressed(original_url)
          end
        end
      rescue => exception
        @image.trace(message: "find image exception", metadata: {exception: exception, backtrace: exception.backtrace})
      end

      def attempt_url_addressed(original_url)
        if reuse_rules.skip?(original_url)
          Librato.increment("image.reuse_skipped")
          @image.trace(message: "skipping reused image", metadata: {original_url: original_url})
          return false
        end

        if Dedupe.attach(original_url, @image)
          Librato.increment("image.dedupe_hit")
          @image.trace(message: "attached existing image", metadata: {original_url: original_url})
          return true
        end

        # Only after the dedupe check: constructing a DownloadCache costs a
        # cache read, wasted on every dedupe hit.
        download_cache = DownloadCache.new(original_url, @image)
        unless download_cache.download?
          @image.trace(message: "skipping image", metadata: {original_url: original_url})
          return false
        end

        download = download_candidate(original_url) or return false

        unless download.valid?
          download.delete!
          download_cache.failed!
          @image.trace(message: "download invalid", metadata: {original_url: original_url})
          return false
        end

        keep(download, original_url)
        enqueue_process
      end

      # Icons mutate under a stable URL, so Dedupe's skip-the-download
      # shortcut is exactly wrong here. Always fetch -- conditionally when
      # possible -- then short-circuit on the original bytes, which skips
      # processing, the expensive part.
      def attempt_content_addressed(original_url)
        row = existing_row

        download = download_candidate(original_url, **validators_for(row, original_url)) or return false

        # Safe to trust: validators are stored per url (see validators_for),
        # so a 304 means this specific source is unchanged.
        if download.not_modified?
          Librato.increment("image.icon_not_modified")
          @image.trace(message: "icon not modified", metadata: {original_url: original_url})
          return true
        end

        unless download.valid?
          download.delete!
          # No DownloadCache.failed!: icons always fetch, so undecodable
          # bytes are retried every crawl with no backoff -- deliberate.
          @image.trace(message: "download invalid", metadata: {original_url: original_url})
          return false
        end

        keep(download, original_url)
        @image.etag          = download.response_etag
        @image.last_modified = download.response_last_modified

        if unchanged?(row)
          Librato.increment("image.icon_unchanged")
          @image.trace(message: "icon unchanged", metadata: {original_url: original_url})
          store_validators(row, original_url)
          FileUtils.rm_f(@image.download_path)
          return true
        end

        enqueue_process
      end

      # A Download, or nil when the request raised.
      def download_candidate(original_url, **validators)
        Download.download!(original_url, minimum_size: @image.preset.minimum_size, **validators)
      rescue => exception
        @image.trace(message: "download exception", metadata: {exception: exception, original_url: original_url})
        nil
      end

      # Moves the file where Process can read it and records what it is.
      def keep(download, original_url)
        @image.download_path        = download.persist!
        @image.final_url            = download.image_url
        @image.original_url         = original_url
        @image.original_fingerprint = Digest::MD5.file(@image.download_path).hexdigest
      end

      def enqueue_process
        Process.perform_async(@image.to_h)
        @image.trace(message: "download valid", metadata: {image_url: @image.final_url})
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

      def combine_urls(image_urls, entry_url)
        image_urls ||= []
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

        page_urls + image_urls
      end

      def reuse_rules
        @reuse_rules ||= ReuseRules.new(@image)
      end
    end
  end
end
