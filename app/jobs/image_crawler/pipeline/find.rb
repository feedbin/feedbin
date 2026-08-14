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

      # Icons mutate under a stable URL, so a row for this URL says nothing
      # about the bytes behind it and Dedupe's skip-the-download shortcut is
      # exactly wrong. Always fetch -- but ask conditionally when we can, then
      # short-circuit on the original bytes. Hashing the original rather than
      # the processed output is what lets this skip *processing*, which for a
      # 32x32 render is the expensive part.
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

        # A 304 now means exactly what this assumes: this specific source is
        # unchanged. It could not mean that before -- the favicons row held one
        # validator pair per host, so sending it to a different candidate
        # invited a 304 for content we had never seen, and 98c39d3e switched
        # the headers off rather than act on it.
        if download.not_modified?
          Librato.increment("image.icon_not_modified")
          Sidekiq.logger.info @image.trace(message: "icon not modified", metadata: {original_url: original_url})
          return true
        end

        unless download.valid?
          download.delete!
          # No DownloadCache.failed! here, unlike download_image: icons always
          # fetch, so a URL that consistently serves undecodable bytes is
          # retried every crawl with no backoff -- deliberate.
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

      # Memoized: provider/provider_id cannot change within a perform, and
      # this is queried once per candidate URL (up to 10). The `defined?`
      # form, not `||=`, so a genuine "no row yet" answer is remembered too
      # instead of re-querying on every remaining candidate.
      def existing_row
        return @existing_row if defined?(@existing_row)
        @existing_row = ::Image.find_by(provider: @image.provider, provider_id: @image.provider_id.to_s)
      end

      # Only for the URL the row actually came from. That restriction is the
      # whole reason conditional requests can be switched back on.
      def validators_for(row, original_url)
        return {} unless row && row.url == original_url
        {etag: row.data["etag"], last_modified: row.data["last_modified"]}
      end

      # The bytes are unchanged but the validators may not be -- a static host
      # that rebuilds emits a fresh ETag for identical content. Store them so
      # the next crawl can get a 304 instead of a download.
      #
      # Guarded on row.url == original_url, mirroring validators_for's read
      # side: a different candidate URL can serve byte-identical bytes (a
      # moved <link rel="icon">, an http/https or www variant), and unchanged?
      # only compares variant and fingerprint, never url. Without this guard,
      # that candidate's validators would be written under this row's url --
      # and with If-Modified-Since, a later, fully conformant server could
      # then confirm a false "unchanged" on the next crawl, since the header
      # only promises "304 if not modified since this date". We could instead
      # refresh row.url to the winning candidate, but Image's
      # before_save :fingerprint_url derives url_fingerprint from url and
      # update_column skips callbacks, so that would silently desync the two.
      # Skipping the write is the correct minimal fix -- the cost is only a
      # missed optimization (we never learn this candidate's validators), not
      # a correctness bug.
      #
      # update_column, not update: updated_at is a view cache key (Phase B) and
      # must move only when the stored bytes move. That makes images.updated_at
      # a content version rather than a row mtime, which is exactly what the
      # touch rule asks for -- not a compromise of it.
      def store_validators(row, original_url)
        return unless row && row.url == original_url
        merged = row.data.merge("etag" => @image.etag, "last_modified" => @image.last_modified).compact
        return if merged == row.data
        row.update_column(:data, merged)
      end

      # Compared in Ruby rather than SQL because the caller already holds the
      # row (for its url and validators). Image.same_fingerprint? is required,
      # not decorative: original_fingerprint is a uuid column and reads back
      # dashed, while every fingerprint we compute is bare hex.
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