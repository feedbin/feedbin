module ImageCrawler
  module Pipeline
    class Process
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("process"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        Sidekiq.logger.info "Process: public_id=#{@image.id} final_url=#{@image.final_url}"

        processor = Processor::Cropper.new(@image.download_path,
          crop:      @image.preset.crop,
          extension: @image.original_extension,
          width:     @image.preset.width,
          height:    @image.preset.height
        )

        if processor.valid?(@image.validate?)
          if @image.unified?
            pair = processor.crop_pair!
            cropped = pair[:jpg]
            webp = pair[:webp]

            @image.webp_path   = webp.file
            @image.bytesize    = webp.size
            @image.fingerprint = webp.fingerprint
          else
            cropped = processor.crop!
            @image.fingerprint = cropped.fingerprint
          end

          @image.processed_path      = cropped.file
          @image.width               = cropped.width
          @image.height              = cropped.height
          @image.placeholder_color   = cropped.placeholder_color
          @image.processed_extension = cropped.extension

          if reuse_rejected?
            Librato.increment("image.reuse_rejected")
            Sidekiq.logger.info "Process: rejecting reused fingerprint public_id=#{@image.id} original_url=#{@image.original_url}"
            discard_processed_files
            requeue_remaining
          else
            Upload.perform_async(@image.to_h)
          end
        else
          requeue_remaining
        end
      ensure
        File.unlink(@image.download_path) rescue Errno::ENOENT
      end

      def requeue_remaining
        return if @image.image_urls.empty?
        image = Image.new_with_attributes(
          id: @image.id,
          preset_name: @image.preset_name,
          image_urls: @image.image_urls,
          provider: @image.provider,
          provider_id: @image.provider_id,
          feed_id: @image.feed_id,
          page_url: @image.page_url,
          meta_image_urls: @image.meta_image_urls
        )
        FindCritical.perform_async(image.to_h)
      end

      def reuse_rejected?
        return false unless @image.unified?
        ReuseRules.new(@image).fingerprint_used_in_feed?(@image.fingerprint)
      end

      def discard_processed_files
        [@image.processed_path, @image.webp_path].compact.each do |path|
          File.unlink(path) rescue Errno::ENOENT
        end
      end
    end
  end
end