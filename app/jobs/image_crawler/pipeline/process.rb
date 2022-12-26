module ImageCrawler
  module Pipeline
    class Process
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("parse"), retry: false

      def perform(image_hash)
        @image = Image.new_from_hash(image_hash)
        Sidekiq.logger.info "Process: public_id=#{@image.id} final_url=#{@image.final_url}"

        processor = Processor::Cropper.new(@image.download_path,
          crop:      @image.preset.crop,
          extension: @image.original_extension,
          width:     @image.preset.width,
          height:    @image.preset.height
        )

        if processor.valid?(@image.validate?)
          cropped = processor.crop!

          @image.processed_path      = cropped.file
          @image.width               = cropped.width
          @image.height              = cropped.height
          @image.placeholder_color   = cropped.placeholder_color
          @image.processed_extension = cropped.extension

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