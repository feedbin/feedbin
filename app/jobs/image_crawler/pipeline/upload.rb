module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload
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
    end
  end
end