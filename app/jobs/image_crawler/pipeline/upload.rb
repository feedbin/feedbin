module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      # Host-local: the processed file is on this disk.
      sidekiq_options queue: local_queue("crawl_critical"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)

        begin
          store
          @image.create_image
          Librato.increment("image.upload")
        rescue => exception
          # No row, so no callback: the receiver would have nothing to read.
          Librato.increment("image.upload_error")
          Sidekiq.logger.info "Upload: write failed id=#{@image.id} exception=#{exception.inspect}"
          return
        end

        @image.enqueue_callback
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_path=#{@image.storage_path} width=#{@image.width} height=#{@image.height}"
      ensure
        FileUtils.rm_f(@image.processed_path)
      end

      def store
        File.open(@image.processed_path) do |file|
          ::Image.storage_client.put_object(::Image.bucket, @image.storage_path, file, @image.storage_options)
        end
      end
    end
  end
end
