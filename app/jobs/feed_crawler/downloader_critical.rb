module FeedCrawler
  class DownloaderCritical
    include Sidekiq::Worker
    sidekiq_options queue: :feed_downloader_critical, retry: false
    def perform(*args)
      Downloader.new.perform(*args, true)
    end
  end
end