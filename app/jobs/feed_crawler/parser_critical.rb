module FeedCrawler
  class ParserCritical
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: local_queue("feed_parser_critical"), retry: false
    def perform(*args)
      Parser.new.perform(*args)
    end
  end
end

