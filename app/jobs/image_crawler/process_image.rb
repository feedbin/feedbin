module ImageCrawler
  class ProcessImage
    include Sidekiq::Worker
    include ImageCrawlerHelper
    include SidekiqHelper

    sidekiq_options queue: local_queue("image_serial"), retry: false

    def perform(public_id, preset_name, original_path, original_url, image_url, candidate_urls)
      @preset_name = preset_name
      Sidekiq.logger.info "ProcessImage: public_id=#{public_id} original_url=#{original_url}"
      image = ImageProcessor.new(original_path, target_width: preset.width, target_height: preset.height)
      if image.valid?
        processed_path = image.send(preset.crop)
        UploadImage.perform_async(public_id, @preset_name, processed_path, original_url, image_url)
      else
        FindImageCritical.perform_async(public_id, @preset_name, candidate_urls) unless candidate_urls.empty?
      end
      begin
        File.unlink(original_path)
      rescue Errno::ENOENT
      end
    end
  end
end