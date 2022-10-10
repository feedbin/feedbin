module ImageCrawler
  class FindImageCritical
    include Sidekiq::Worker
    sidekiq_options queue: :crawl_critical, retry: false
    def perform(*args)
      FindImage.new.perform(*args)
    end
  end
end