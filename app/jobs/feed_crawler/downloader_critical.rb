module FeedCrawler
  class DownloaderCritical
    include Sidekiq::Worker
    sidekiq_options queue: :feed_downloader_critical, retry: false
    def perform(*args)
      job = Downloader.new
      job.critical = true
      job.perform(*args)
    end
  end
end