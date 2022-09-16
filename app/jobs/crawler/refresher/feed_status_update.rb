# frozen_string_literal: true

module Crawler
  module Refresher
    class FeedStatusUpdate
      include Sidekiq::Worker
      sidekiq_options queue: :feed_downloader_critical

      def perform(feed_id, exception = nil)
        if exception
          FeedStatus.new(feed_id).error!(exception, formatted: true)
        else
          FeedStatus.clear!(feed_id)
        end
      end

    end
  end
end