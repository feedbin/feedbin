module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        storage_url = upload
        storage_url_next = upload_next
        @image.bytesize = File.size(@image.processed_path)
        @image.storage_url = storage_url
        @image.storage_url_next = storage_url_next
        @image.send_to_feedbin

        DownloadCache.save(@image)
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_url=#{@image.storage_url} width=#{@image.width} height=#{@image.height}"
      ensure
        File.unlink(@image.processed_path)
      end

      def upload
        File.open(@image.processed_path) do |file|
          options = STORAGE.dup
          options = options.merge(region: @image.preset.region) unless @image.preset.region.nil?
          response = Fog::Storage.new(options).put_object(@image.bucket, @image.image_name, file, @image.storage_options)
          URI::HTTPS.build(
            host: response.data[:host],
            path: response.data[:path]
          ).to_s
        end
      end

      def upload_next
        File.open(@image.processed_path) do |file|
          options = STORAGE.dup
          response = Fog::Storage.new(options).put_object(@image.bucket, @image.storage_path, file, @image.storage_options)
          URI::HTTPS.build(
            host: response.data[:host],
            path: response.data[:path]
          ).to_s
        end
      end
    end
  end
end