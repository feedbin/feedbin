module FeedCrawler
  class DownloaderMigration
    include Sidekiq::Worker
    include SidekiqHelper

    SET_NAME = "#{name}-updates"

    def perform
      updates = dequeue_ids(SET_NAME)
      return if updates.blank?
      Sidekiq.logger.info "Migrating count=#{updates.count}"
      updates = updates.map {JSON.load(_1)}
      updates = updates.each_with_object({}) do |update, hash|
        hash[update["id"]] = JSON.dump(update["crawl_data"])
      end
      Feed.update_multiple(column: :crawl_data, data: updates)
    end

    def update_all
      Feed.xml.find_in_batches(batch_size: 1000) do |feeds|
        puts feeds.first.id
        data = feeds.each_with_object({}) do |feed, hash|
          hash[feed.id] = build_data(feed.id)
        end
        Feed.update_multiple(column: :crawl_data, data: data)
      end
    end

    private

    def build_data(feed_id)
      feed_cache = FeedCache.new(feed_id)
      JSON.dump({
        etag:                 feed_cache.etag,
        last_modified:        feed_cache.last_modified,
        downloaded_at:        feed_cache.downloaded_at,
        download_fingerprint: feed_cache.checksum,
        error_count:          feed_cache.attempt_count,
        redirected_to:        feed_cache.redirect,
        last_error:           feed_cache.last_error,
      })
    end
  end
end
