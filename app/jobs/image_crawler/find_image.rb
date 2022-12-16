module ImageCrawler
  class FindImage
    include Sidekiq::Worker
    include ImageCrawlerHelper
    sidekiq_options queue: :crawl_images, retry: false

    def perform(public_id, preset_name, candidate_urls, entry_url = nil)
      @public_id = public_id
      @preset_name = preset_name
      @entry_url = entry_url
      @candidate_urls = combine_urls(candidate_urls)
      timer = Timer.new(45)
      count = 0

      while original_url = @candidate_urls.shift
        count += 1

        if count > 10
          Sidekiq.logger.info "Exceeded count limit: public_id=#{@public_id} count=#{count}"
          break
        end

        if timer.expired?
          Sidekiq.logger.info "Exceeded total time limit: public_id=#{@public_id} elapsed_time=#{timer.elapsed}"
          break
        end

        Sidekiq.logger.info "Candidate: public_id=#{@public_id} original_url=#{original_url} count=#{count}"

        download_cache = DownloadCache.copy(original_url, public_id: @public_id, preset_name: @preset_name)
        if download_cache.copied?
          send_to_feedbin(original_url: download_cache.image_url, storage_url: download_cache.storage_url, placeholder_color: download_cache.placeholder_color)
          Sidekiq.logger.info "Copied image: public_id=#{@public_id} image_url=#{download_cache.image_url} storage_url=#{download_cache.storage_url}"
          break
        elsif download_cache.download?
          break if download_image(original_url, download_cache)
        else
          Sidekiq.logger.info "Skipping download: public_id=#{@public_id} original_url=#{original_url}"
        end

      end
    end

    def download_image(original_url, download_cache)
      found = false
      download = Download.download!(original_url, minimum_size: preset.minimum_size)
      if download.valid?
        found = true
        ProcessImage.perform_async(@public_id, @preset_name, download.persist!, original_url, download.image_url, @candidate_urls)
        Sidekiq.logger.info "Download valid: public_id=#{@public_id} image_url=#{download.image_url}"
      else
        download.delete!
        download_cache.save(storage_url: false, image_url: false, placeholder_color: nil)
        Sidekiq.logger.info "Download invalid: public_id=#{@public_id} original_url=#{original_url}"
      end
      found
    rescue => exception
      download&.delete!
      Sidekiq.logger.info "Download failed: exception=#{exception.inspect} original_url=#{original_url}"
      false
    end

    def combine_urls(candidate_urls)
      return candidate_urls unless @entry_url

      if Download.find_download_provider(@entry_url)
        page_urls = [@entry_url]
        Sidekiq.logger.info "Recognized URL: public_id=#{@public_id} entry_url=#{@entry_url}"
      else
        page_urls = MetaImages.find_urls(@entry_url)
        Sidekiq.logger.info "MetaImages: public_id=#{@public_id} count=#{page_urls&.length || 0} entry_url=#{@entry_url}"
      end
      page_urls ||= []
      page_urls.concat(candidate_urls)
    end
  end
end