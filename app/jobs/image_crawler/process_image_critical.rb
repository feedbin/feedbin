module ImageCrawler
  class ProcessImageCritical
    include Sidekiq::Worker
    include SidekiqHelper

    sidekiq_options queue: local_queue("image_serial_critical"), retry: false

    def perform(*args)
      ProcessImage.new.perform(*args)
    end
  end
end