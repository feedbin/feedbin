module ImageCrawler
  module Pipeline
    # Upload for a live image. Same work, on a queue the backfill never
    # touches, weighted above crawl_<host> in the worker config.
    class UploadCritical
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl_critical"), retry: false

      def perform(*args)
        Upload.new.perform(*args)
      end
    end
  end
end
