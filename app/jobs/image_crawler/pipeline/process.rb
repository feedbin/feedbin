module ImageCrawler
  module Pipeline
    class Process
      include Sidekiq::Worker
      include SidekiqHelper

      # Host-local: the downloaded file is on this disk.
      sidekiq_options queue: local_queue("process_critical"), retry: false

      # The attributes that describe the request rather than a candidate: what
      # Find needs to try the rest of the urls.
      REQUEST_ATTRIBUTES = %i[id kind preset_name image_urls provider provider_id feed_id page_url meta_image_urls context]

      def perform(image_hash)
        @image = Image.new(image_hash)
        Sidekiq.logger.info "Process: public_id=#{@image.id} final_url=#{@image.final_url}"

        processor = Processor::Cropper.new(@image.download_path,
          crop:   @image.preset.crop,
          width:  @image.preset.width,
          height: @image.preset.height
        )

        if processor.valid?(@image.validate?)
          cropped = processor.crop!

          @image.processed_path    = cropped.file
          @image.bytesize          = cropped.size
          @image.fingerprint       = cropped.fingerprint
          @image.width             = cropped.width
          @image.height            = cropped.height
          @image.placeholder_color = cropped.placeholder_color

          if reuse_rejected?
            Librato.increment("image.reuse_rejected")
            Sidekiq.logger.info "Process: rejecting reused fingerprint public_id=#{@image.id} original_url=#{@image.original_url}"
            FileUtils.rm_f(@image.processed_path)
            requeue_remaining
          else
            Upload.perform_async(@image.to_h)
          end
        else
          requeue_remaining
        end
      ensure
        FileUtils.rm_f(@image.download_path)
      end

      def requeue_remaining
        return if @image.image_urls.empty?
        FindCritical.perform_async(@image.to_h.slice(*REQUEST_ATTRIBUTES))
      end

      def reuse_rejected?
        return false if @image.content_addressed?
        ReuseRules.new(@image).fingerprint_used_in_feed?(@image.fingerprint)
      end
    end
  end
end
