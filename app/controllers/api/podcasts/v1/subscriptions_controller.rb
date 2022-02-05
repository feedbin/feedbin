module Api
  module Podcasts
    module V1
      class SubscriptionsController < ApiController
        before_action :set_subscription, only: [:destroy]
        before_action :validate_content_type, only: [:create]

        def index
          @user = current_user
          @subscriptions = @user
            .subscriptions
            .preload(:feed)
            .order(created_at: :desc)
            .where.not(show_status: :not_show)
        end

        def create
          @user = current_user
          feeds = FeedFinder.feeds(params[:feed_url])
          if feeds.length == 0
            status_not_found
          else
            @feed = feeds.first
            @subscription = @user.subscriptions.create_with(show_status: :hidden).find_or_create_by(feed: @feed)
            @subscription.update(subscription_params)
            status = @user.subscribed_to?(@feed) ? :found : :created
            render status: status, location: api_podcasts_v1_subscription_url(@subscription, format: :json)
          end
        rescue => exception
          if Rails.env.production?
            status_not_found
            Honeybadger.notify(e)
          else
            raise exception
          end
        end

        def destroy
          @subscription.destroy
          head :no_content
        end

        private

        def subscription_params
          params.require(:subscription).permit(:show_status)
        end

        def set_subscription
          @subscription = @user.subscriptions.find(params[:id])
        end
      end
    end
  end
end