module Api
  module Podcasts
    module V1
      class SubscriptionsController < ApiController
        before_action :set_subscription, only: [:destroy, :update]
        before_action :validate_content_type, only: [:create, :update]

        wrap_parameters PodcastSubscription

        def index
          @user = current_user
          @subscriptions = @user
            .podcast_subscriptions
            .preload(:feed)
            .order(created_at: :desc)
        end

        def create
          @user = current_user

          feeds = Feed.xml.where(feed_url: params[:feed_url])
          if feeds.length == 0
            feeds = FeedFinder.feeds(params[:feed_url])
          end

          if feeds.length == 0
            status_not_found
          else
            @feed = feeds.first
            subscribed = @user.podcast_subscriptions.where(feed: @feed).exists?
            @subscription = @user.podcast_subscriptions.find_or_create_by(feed: @feed)
            @subscription.update(subscription_params)

            status = subscribed ? :found : :created
            render status: status, location: api_podcasts_v1_subscription_url(@subscription, format: :json)
          end
        rescue => exception
          if Rails.env.production?
            status_not_found
            ErrorService.notify(e)
          else
            raise exception
          end
        end

        def update
          update_params = remove_stale_updates(@subscription, subscription_params, params)
          @subscription.update(update_params)
          head :no_content
        end

        def destroy
          @subscription.destroy
          head :no_content
        end

        private

        def subscription_params
          params.require(:podcast_subscription).permit(:status, :playlist_id, :chapter_filter, :chapter_filter_type, :download_filter, :download_filter_type)
        end

        def set_subscription
          @subscription = @user.podcast_subscriptions.find_by_feed_id!(params[:id])
        end
      end
    end
  end
end