module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload if @image.legacy_store?
        r2_stored = false

        if @image.unified?
          begin
            upload_r2
            @image.create_image
            Librato.increment("image.r2_upload")
            r2_stored = true
          rescue => exception
            # Degrade to the legacy path: the S3 object exists, so the entry
            # still gets an image. A partial failure can orphan an R2 object
            # (no row references it) — accepted dust.
            Librato.increment("image.r2_error")
            Sidekiq.logger.info "Upload: R2 write failed, serving legacy only id=#{@image.id} exception=#{exception.inspect}"
          end

          # Confirmatory, and deliberately outside the block above: both
          # writes already succeeded by here, so a HEAD that could not be
          # performed is not evidence that anything went wrong, and must not
          # retract a store that may well be fine. Only a confirmed,
          # unrecoverable loss does -- ensure_stored returns false for that
          # one case, and only that one.
          r2_stored = ensure_stored if r2_stored
        end

        DownloadCache.save(@image) unless r2_stored
        @image.send_to_feedbin(include_unified: r2_stored)
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_url=#{@image.storage_url} width=#{@image.width} height=#{@image.height}"
      ensure
        File.unlink(@image.processed_path)
        begin
          File.unlink(@image.webp_path) if @image.webp_path
        rescue Errno::ENOENT
        end
      end

      def upload
        File.open(@image.processed_path) do |file|
          options = STORAGE.dup
          options = options.merge(region: @image.preset.region) unless @image.preset.region.nil?
          response = Fog::Storage.new(options).put_object(@image.bucket, @image.image_name, file, @image.storage_options)

          klass = Rails.env.development? ? URI::HTTP : URI::HTTPS

          uri = klass.build(
            host: response.data[:host],
            path: response.data[:path]
          )

          if Rails.env.development?
            uri.port = response.data[:port]
          end

          uri.to_s
        end
      end

      def upload_r2
        File.open(@image.r2_source_path) do |file|
          Fog::Storage.new(STORAGE_R2).put_object(@image.r2_bucket, @image.storage_path, file, @image.r2_storage_options)
        end
      end

      # create_image is the first moment this crawl's row references this
      # object -- true for every unified? preset, not just the
      # content-addressed ones. Until then a garbage-collection sweep sees
      # the path as unreferenced and is entitled to delete it, and that loss
      # is permanent -- but the guard against it differs by preset. For a
      # content-addressed preset, Find's unchanged? matches a later crawl's
      # row on original_fingerprint and skips reprocessing just because that
      # row exists, without checking that its object still does. For the
      # other unified presets, Dedupe#attach makes the same mistake from the
      # other direction: it only checks that a row exists for the url, not
      # that its object does, so it would keep attaching new rows to a dead
      # path. (Content-addressed presets never reach Dedupe#attach -- Find
      # dispatches content_addressed? to attempt_icon before unified? is
      # even tested.)
      #
      # The lock serializes the sweep against create_image, so the object's
      # fate is settled by the time we get here -- but "the row exists"
      # only protects the path for as long as the row exists, and the
      # re-upload below runs outside the lock. So this does not guarantee
      # the object survives forever after; it guarantees perform never
      # returns having left a row it knows points at nothing. A confirmed,
      # unrecoverable loss drops the row (see resurrect's rescue) rather
      # than leaving it dangling; a merely-unconfirmable check leaves it in
      # place, because it is not evidence of anything.
      def ensure_stored
        Fog::Storage.new(STORAGE_R2).head_object(@image.r2_bucket, @image.storage_path)
        true
      rescue Excon::Errors::NotFound
        resurrect
      rescue => exception
        # Not a 404: we don't know whether the object is there, only that we
        # couldn't check. The write already happened, so this is unconfirmed,
        # not failed -- returning false here would retract a store that may
        # well be fine.
        Librato.increment("image.r2_confirm_error")
        Sidekiq.logger.info "Upload: could not confirm storage, leaving row as-is id=#{@image.id} storage_path=#{@image.storage_path} exception=#{exception.inspect}"
        true
      end

      # Split from ensure_stored into its own method rather than a nested
      # rescue inside ensure_stored's rescue Excon::Errors::NotFound branch:
      # Ruby will not let a sibling rescue on the same begin catch an
      # exception raised inside another rescue clause of that begin, so
      # without the split a failed re-upload here would escape ensure_stored
      # entirely, crashing this retry: false job and leaving the row
      # dangling on an object confirmed gone.
      def resurrect
        Librato.increment("image.r2_resurrected")
        Sidekiq.logger.info "Upload: object vanished before the row existed, re-uploading id=#{@image.id} storage_path=#{@image.storage_path}"
        upload_r2
        true
      rescue => exception
        # The object is confirmed gone and we could not put it back. A row
        # pointing at nothing is worse than no row (see drop_image), so
        # retract: drop the row and report the store as failed.
        Librato.increment("image.r2_error")
        Sidekiq.logger.info "Upload: re-upload after vanish also failed, dropping the row id=#{@image.id} storage_path=#{@image.storage_path} exception=#{exception.inspect}"
        @image.drop_image
        false
      end
    end
  end
end
