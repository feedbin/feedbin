module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload
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
        File.open(@image.webp_path) do |file|
          Fog::Storage.new(STORAGE_R2).put_object(@image.r2_bucket, @image.storage_path, file, @image.r2_storage_options)
        end
      end
    end
  end
end
