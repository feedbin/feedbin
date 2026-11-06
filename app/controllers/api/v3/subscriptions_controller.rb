module Api
  module V3
    class SubscriptionsController < ApiController
      include SubscriptionScoped

      PREFERENCES = %w[muted media_only show_updates].freeze
      CANDIDATE_EXPANSIONS = %w[tags].freeze

      before_action :set_subscription, only: [:show, :update, :destroy]

      rescue_from FeedCandidates::Failure do |failure|
        render_problem :unprocessable_content, failure.code,
          title: failure.title, detail: failure.message, http_code: failure.http_code
      end

      def index
        data = serialize(subscriptions)
        return if not_modified?(etag_for("subscriptions", digest(data)))
        render_list(data)
      end

      def show
        render json: serialize([@subscription]).first
      end

      # Routed as POST so feed passwords never land in a URL.
      def new
        expand = expansions(CANDIDATE_EXPANSIONS)
        candidates = FeedCandidates.new(@user, candidate_query, **feed_credentials).candidates
        render json: candidates_body(candidates, expand)
      end

      def create
        render json: Subscribe.new(@user, body).subscribe
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
        subscriptions.map { SubscriptionSerializer.new(it, tags: tags.fetch(it.feed_id, []), feed: feeds[it.feed_id], expand: expand).to_h }
      end

      def candidate_query
        required_string("q")
      end

      def feed_credentials
        {username: optional_string("feed_username"), password: optional_string("feed_password")}
      end

      def candidates_body(candidates, expand)
        list = {object: "list", data: candidates.map { FeedSerializer.new(it.feed, candidate: {subscription_id: it.subscription&.id, daily_entry_counts: it.daily_entry_counts}).to_h }}
        if expand.include?("tags")
          list[:tags] = TagList.new(@user).each_with_subscription_ids.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h }
        end
        list
      end

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
