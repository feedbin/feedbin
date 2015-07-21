module Api
  module V2
    class SuggestedFeedsController < ApiController

      respond_to :json

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
          render nothing: true, status: :created
        else
          render nothing: true, status: :bad_request
        end

      end

      def unsubscribe
        @user = current_user
        suggested_feed = SuggestedFeed.find(params[:id])
        feed = suggested_feed.feed

        @user.subscriptions.where(feed: feed).destroy_all

        if !@user.subscribed_to?(feed.id)
          render nothing: true, status: :no_content
        else
          render nothing: true, status: :bad_request
        end

      end


    end
  end
end
