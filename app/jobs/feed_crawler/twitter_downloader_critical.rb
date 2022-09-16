module FeedCrawler
  class TwitterDownloaderCritical
    include Sidekiq::Worker
    sidekiq_options queue: :twitter_refresher_critical, retry: false
    def perform(*args)
      TwitterDownloader.new.perform(*args)
    end
  end
end