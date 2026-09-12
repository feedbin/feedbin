module ImageCrawler
  module Pipeline
    # Process for a live image. Same work, on a queue the backfill never
    # touches, weighted above process_<host> in the worker config.
    class ProcessCritical
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("process_critical"), retry: false

      def perform(*args)
        Process.new.perform(*args)
      end
    end
  end
end
