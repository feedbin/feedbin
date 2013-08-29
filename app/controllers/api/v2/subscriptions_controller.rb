module Api
  module V2
    class SubscriptionsController < ApiController

      respond_to :json

      before_action :validate_content_type, only: [:create]
      before_action :validate_create, only: [:create]

      def index
        @user = current_user
        @subscriptions = @user.subscriptions.includes(:feed).order("subscriptions.created_at DESC")
        if params.has_key?(:since)
          time = Time.iso8601(params[:since])
          @subscriptions = @subscriptions.where("subscriptions.created_at > :time", {time: time})
        end
        if @subscriptions.any?
          fresh_when(etag: @subscriptions, last_modified: @subscriptions.maximum(:updated_at))
        else
          @subscriptions = []
        end
      end

      def show
        @user = current_user
        @subscription = @user.subscriptions.where(id: params[:id]).first
        if @subscription.present?
          fresh_when(@subscription)
        else
          status_forbidden
        end
      end

      def create
        @user = current_user
        begin
          result = FeedFetcher.new(params[:feed_url]).create_feed!
          if result.feed
            status = @user.subscribed_to?(result.feed) ? :found : :created
            @subscription = @user.safe_subscribe(result.feed)
            render status: status, location: api_v2_subscription_url(@subscription, format: :json)
          elsif result.feed_options.any?
            @options = result.feed_options
            render status: :multiple_choices
          else
            status_not_found
          end
        rescue Exception => e
          status_not_found
          Honeybadger.notify(e)
        end
      end

      def destroy
        @user = current_user
        @subscription = @user.subscriptions.find(params[:id])
        if @subscription.present?
          @subscription.destroy
          @subscription.feed.tag('', @user)
          render nothing: true, status: :no_content
        else
          status_forbidden
        end
      end

      def update
        @user = current_user
        @subscription = @user.subscriptions.find(params[:id])
        if @subscription.present?
          @subscription.attributes = subscription_params
          @subscription.save
        else
          status_forbidden
        end
      end

      private

      def subscription_params
        params.require(:subscription).permit(:title)
      end

      def validate_create
        needs 'feed_url'
      end

    end
  end
end