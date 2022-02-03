module Api
  module Public
    module V1
      class FeedsController < ApiController
        def show
          url = hex_decode(params[:id])
          @feed = Feed.find_by_feed_url(url)
          if @feed.present?
            if @feed.standalone_request_at.blank?
              FeedStatus.new.perform(@feed.id)
              FeedUpdate.new.perform(@feed.id)
            end
          else
            feeds = FeedFinder.feeds(url)
            @feed = feeds.first
          end

          if @feed.present?
            @feed.touch(:standalone_request_at)
          end
        end
      end
    end
  end
end