module ImageCrawler
  class ProcessImage
    include Sidekiq::Worker
    include ImageCrawlerHelper
    include SidekiqHelper

    sidekiq_options queue: local_queue("parse"), retry: false

    def perform(public_id, preset_name, original_path, original_url, image_url, candidate_urls)
      @preset_name = preset_name
      Sidekiq.logger.info "ProcessImage: public_id=#{public_id} image_url=#{image_url}"
      image = ImageProcessor.new(original_path, target_width: preset.width, target_height: preset.height)

      if image.valid? || !preset.validate
        processed_path = image.send(preset.crop)
        UploadImage.perform_async(public_id, @preset_name, processed_path, original_url, image_url, image.color)
      else
        FindImageCritical.perform_async(public_id, @preset_name, candidate_urls) unless candidate_urls.empty?
      end
    ensure
      File.unlink(original_path) rescue Errno::ENOENT
    end
  end
end