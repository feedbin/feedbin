module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      DEFAULT_PORTS = {"http" => 80, "https" => 443}.freeze

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload if @image.legacy_store?
        unified_stored = false

        if @image.unified?
          begin
            upload_unified
            @image.create_image
            Librato.increment("image.unified_upload")
            unified_stored = true
          rescue => exception
            Librato.increment("image.unified_error")

            # Nothing to degrade to. The entry presets stopped writing legacy
            # objects after the S3 backfill, so a callback here would hand the
            # receiver a processed_url for an object nobody wrote. Drop the
            # image instead and let the next crawl retry it.
            unless @image.legacy_store?
              Sidekiq.logger.info "Upload: unified write failed, no legacy fallback id=#{@image.id} exception=#{exception.inspect}"
              return
            end

            # Degrade to the legacy path: the legacy object exists, so the entry
            # still gets an image. A partial failure can orphan a unified object
            # (no row references it) — accepted dust.
            Sidekiq.logger.info "Upload: unified write failed, serving legacy only id=#{@image.id} exception=#{exception.inspect}"
          end
        end

        DownloadCache.save(@image) unless unified_stored
        @image.send_to_feedbin(include_unified: unified_stored)
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_url=#{@image.storage_url} width=#{@image.width} height=#{@image.height}"
      ensure
        File.unlink(@image.processed_path)
      end

      def upload
        File.open(@image.processed_path) do |file|
          options = STORAGE.dup
          options = options.merge(region: @image.preset.region) unless @image.preset.region.nil?
          response = Fog::Storage.new(options).put_object(@image.bucket, @image.image_name, file, @image.storage_options)

          object_url(response.data)
        end
      end

      # Describe the connection Fog actually made. Keying the scheme off
      # Rails.env instead produced http://host:443/path in development, which is
      # plaintext against a TLS port.
      def object_url(data)
        # Fog always reports the scheme on a real request. Default it anyway,
        # because a nil scheme builds an empty string, and a blank storage_url
        # fails silently at read time.
        scheme = data[:scheme] || "https"
        port = data[:port]

        URI::Generic.build(
          scheme: scheme,
          host: data[:host],
          port: (port unless port == DEFAULT_PORTS[scheme]),
          path: data[:path]
        ).to_s
      end

      # Both stores get the same bytes: one encoding per image now.
      def upload_unified
        File.open(@image.processed_path) do |file|
          ::Image.unified_client.put_object(@image.unified_bucket, @image.storage_path, file, @image.unified_storage_options)
        end
      end
    end
  end
end
