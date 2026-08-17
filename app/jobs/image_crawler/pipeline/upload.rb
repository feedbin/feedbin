module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

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
            # Degrade to the legacy path: the legacy object exists, so the entry
            # still gets an image. A partial failure can orphan a unified object
            # (no row references it) — accepted dust.
            Librato.increment("image.unified_error")
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

      # Both stores get the same bytes: one encoding per image now.
      def upload_unified
        File.open(@image.processed_path) do |file|
          ::Image.unified_client.put_object(@image.unified_bucket, @image.storage_path, file, @image.unified_storage_options)
        end
      end
    end
  end
end
