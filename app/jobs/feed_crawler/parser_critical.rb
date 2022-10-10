module FeedCrawler
  class ParserCritical
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: local_queue("parse_critical"), retry: false
    def perform(*args)
      Parser.new.perform(*args)
    end
  end
end

