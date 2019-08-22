module Api
  module V2
    class SubscriptionsController < ApiController
      respond_to :json

      before_action :validate_content_type, only: [:create]
      before_action :validate_create, only: [:create]

      def index
        if request.head?
          render status: 200
        else
          @user = current_user
          @user.update(api_client: request.user_agent)
          respond_to do |format|
            format.json do
              @subscriptions = @user.subscriptions.includes(:feed).order("subscriptions.created_at DESC")
              if params.key?(:since)
                time = Time.iso8601(params[:since])
                @subscriptions = @subscriptions.where("subscriptions.created_at > :time", {time: time})
              end
              if @subscriptions.present?
                fresh_when(etag: @subscriptions, last_modified: @subscriptions.maximum(:updated_at))
              else
                @subscriptions = []
              end
            end
            format.xml do
              @tags = @user.feed_tags
              @feeds = @user.feeds
              @titles = {}
              @user.subscriptions.pluck(:feed_id, :title).each do |feed_id, title|
                @titles[feed_id] = title
              end
              render template: "subscriptions/index"
            end
          end
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
        finder = FeedFinder.new(params[:feed_url])
        begin
          feeds = finder.create_feeds!
        rescue
          feeds = []
        end

        if feeds.length == 0
          status_not_found
        elsif feeds.length == 1
          feed = feeds.first
          status = @user.subscribed_to?(feed) ? :found : :created
          @subscription = @user.subscriptions.find_or_create_by(feed: feed)
          render status: status, location: api_v2_subscription_url(@subscription, format: :json)
        else
          @options = feeds
          render status: :multiple_choices
        end
      rescue Exception => e
        status_not_found
        Honeybadger.notify(e)
      end

      def destroy
        @user = current_user
        @subscription = @user.subscriptions.find(params[:id])
        if @subscription.present?
          @subscription.destroy
          @subscription.feed.tag("", @user)

          # touch generated subscriptions that cannot be destroyed
          # this will help them get reloaded in clients
          @subscription.touch unless @subscription.destroyed?
          head :no_content
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
        needs "feed_url"
      end
    end
  end
end
