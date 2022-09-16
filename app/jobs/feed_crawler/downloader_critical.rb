module FeedCrawler
  class FeedDownloaderCritical
    include Sidekiq::Worker
    sidekiq_options queue: :feed_downloader_critical, retry: false
    def perform(*args)
      FeedDownloader.new.perform(*args, true)
    end
  end
end