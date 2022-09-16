module ImageCrawler
  class ProcessImageCritical
    include Sidekiq::Worker
    sidekiq_options queue: "image_serial_critical_#{Socket.gethostname}", retry: false
    def perform(*args)
      ProcessImage.new.perform(*args)
    end
  end
end