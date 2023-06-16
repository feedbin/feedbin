module Api
  module Podcasts
    module V1
      class FeedsController < ApiController
        skip_before_action :authorize
        skip_before_action :set_user

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
          else
            status_not_found
          end
        rescue => exception
          if Rails.env.production?
            ErrorService.notify(exception)
            status_not_found
          else
            raise exception
          end
        end
      end
    end
  end
end