module Api
  module V2
    class SuggestedFeedsController < ApiController
      respond_to :json
      skip_before_action :valid_user

      def index
        @suggested_feeds = SuggestedFeed.limit(200).includes(:feed)
      end

      def subscribe
        @user = current_user
        suggested_feed = SuggestedFeed.find(params[:id])
        feed = suggested_feed.feed

        begin
          @user.subscriptions.create!(feed: feed)
        rescue Exception
        end

        if @user.subscribed_to?(feed.id)
          head :created
        else
          head :bad_request
        end
      end

      def unsubscribe
        @user = current_user
        suggested_feed = SuggestedFeed.find(params[:id])
        feed = suggested_feed.feed

        @user.subscriptions.where(feed: feed).destroy_all

        if !@user.subscribed_to?(feed.id)
          head :no_content
        else
          head :bad_request
        end
      end
    end
  end
end
