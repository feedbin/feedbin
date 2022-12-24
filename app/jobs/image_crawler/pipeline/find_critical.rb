module ImageCrawler
  module Pipeline
    class FindCritical
      include Sidekiq::Worker
      sidekiq_options queue: :crawl_critical, retry: false
      def perform(*args)
        Find.new.perform(*args)
      end
    end
  end
end