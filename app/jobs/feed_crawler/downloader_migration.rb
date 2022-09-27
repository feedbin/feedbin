module FeedCrawler
  class DownloaderMigration
    include Sidekiq::Worker
    include SidekiqHelper

    SET_NAME = "#{name}-updates"

    def perform
      updates = dequeue_ids(SET_NAME)
      return if updates.blank?
      updates = updates.map {JSON.load(_1)}
      updates = updates.each_with_object({}) do |update, hash|
        hash[update["id"]] = JSON.dump(update["crawl_data"])
      end
      Feed.update_multiple(column: :crawl_data, data: updates)
    end
  end
end
