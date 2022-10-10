module ImageCrawler
  class ProcessImageCritical
    include Sidekiq::Worker
    include SidekiqHelper

    sidekiq_options queue: local_queue("parse_critical"), retry: false

    def perform(*args)
      ProcessImage.new.perform(*args)
    end
  end
end