module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload

        if @image.unified?
          upload_r2
          @image.create_image
          Librato.increment("image.r2_upload")
        else
          DownloadCache.save(@image)
        end

        @image.send_to_feedbin
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
