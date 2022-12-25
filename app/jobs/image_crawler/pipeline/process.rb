module ImageCrawler
  module Pipeline
    class Process
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("parse"), retry: false

      def perform(image_hash)
        @image = Image.new_from_hash(image_hash)
        Sidekiq.logger.info "Process: public_id=#{@image.id} final_url=#{@image.final_url}"

        processor = ImageProcessor.new(@image.download_path,
          target_width: @image.preset.width,
          target_height: @image.preset.height,
          crop: @image.preset.crop
        )

        if !@image.validate? || processor.valid?
          path = processor.crop!

          @image.processed_path    = path
          @image.width             = processor.final_width
          @image.height            = processor.final_height
          @image.placeholder_color = processor.placeholder_color

          Upload.perform_async(@image.to_h)
        else
          FindCritical.perform_async(@image.id, @image.preset_name, @image.image_urls) unless @image.image_urls.empty?
        end
      ensure
        File.unlink(@image.download_path) rescue Errno::ENOENT
      end
    end
  end
end