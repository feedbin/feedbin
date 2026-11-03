module Api
  module V3
    # The user's subscriptions: one response with an ETag, ids by default,
    # expand=feed,tags to embed the objects; subscribe by URL, search words
    # or feed id (Subscribe); retitle and set preferences; unsubscribe. The
    # tag set and the OPML export are under Subscriptions::.
    class SubscriptionsController < ApiController
      include SubscriptionScoped

      PREFERENCES = %w[muted media_only show_updates].freeze

      before_action :set_subscription, only: [:show, :update, :destroy]

      def index
        data = serialize(subscriptions)
        return if not_modified?(etag_for("subscriptions", digest(data)))
        render_list(data)
      end

      def show
        render json: serialize([@subscription]).first
      end

      # Exactly one feed subscribes (201, or 200 when already subscribed);
      # several are a 300 with the candidates; none is a 404.
      def create
        subscribe = Subscribe.new(@user, body)
        feeds = subscribe.feeds
        return status_not_found if feeds.empty?
        return render_choices(subscribe) if feeds.many?

        subscription, created = subscribe.subscribe
        render json: serialize([subscription]).first, status: created ? :created : :ok
      end

      def update
        @subscription.update!(subscription_params)
        render json: serialize([@subscription]).first
      end

      def destroy
        @subscription.destroy
        head :no_content
      end

      private

      def subscriptions
        scope = subscription_list.subscriptions.order(:id)
        scope = scope.includes(feed: [*Feed::ICON_PRELOADS, :touch_icon_image_record]) if expansions(SubscriptionSerializer::EXPANSIONS).include?("feed")
        scope.to_a
      end

      def serialize(subscriptions)
        expand = expansions(SubscriptionSerializer::EXPANSIONS)
        feeds = expand.include?("feed") ? serialize_feeds(subscriptions.map(&:feed)) : {}
        tags = subscription_list.tags_by_feed_id
        subscriptions.map { SubscriptionSerializer.new(_1, tags: tags.fetch(_1.feed_id, []), feed: feeds[_1.feed_id], expand: expand).to_h }
      end

      def render_choices(subscribe)
        subscribe.offer
        render json: {object: "list", data: subscribe.feeds.map { FeedSerializer.new(_1).to_h }}, status: :multiple_choices
      end

      # A merge patch: custom_title (null clears it) and preferences key by
      # key.
      def subscription_params
        attributes = {}
        if body.key?("custom_title")
          attributes[:title] = optional_string("custom_title", detail: "custom_title must be a string or null.").presence
        end
        if body.key?("preferences")
          object("preferences").slice(*PREFERENCES).each { |key, value| attributes[key] = boolean("preferences/#{key}", value) }
        end
        attributes
      end
    end
  end
end
