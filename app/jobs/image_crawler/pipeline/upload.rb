module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)

        begin
          upload_unified
          @image.create_image
          Librato.increment("image.unified_upload")
        rescue => exception
          # Nothing to fall back to: the unified store is the only one, so a
          # callback here would hand the receiver a row nobody wrote. Drop
          # the image instead and let the next crawl retry it.
          Librato.increment("image.unified_error")
          Sidekiq.logger.info "Upload: unified write failed id=#{@image.id} exception=#{exception.inspect}"
          return
        end

        @image.send_to_feedbin
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_path=#{@image.storage_path} width=#{@image.width} height=#{@image.height}"
      ensure
        File.unlink(@image.processed_path)
      end

      def upload_unified
        File.open(@image.processed_path) do |file|
          ::Image.unified_client.put_object(@image.unified_bucket, @image.storage_path, file, @image.unified_storage_options)
        end
      end
    end
  end
end
