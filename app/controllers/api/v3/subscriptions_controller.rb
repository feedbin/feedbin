module Api
  module V3
    # The user's subscriptions: one response with an ETag, ids by default,
    # expand=feed,tags to embed the objects; the feeds a URL or search words
    # offer (FeedCandidates); subscribe to several at once (Subscribe);
    # retitle and set preferences; unsubscribe. The tag set and the OPML
    # export are under Subscriptions::.
    class SubscriptionsController < ApiController
      include SubscriptionScoped

      PREFERENCES = %w[muted media_only show_updates].freeze
      CANDIDATE_EXPANSIONS = %w[tags].freeze

      before_action :set_subscription, only: [:show, :update, :destroy]

      rescue_from FeedCandidates::CredentialsRequired do
        render_problem :unprocessable_content, "credentials_required",
          title: "Credentials required",
          detail: "The site needs a username and password. Send them as feed_username and feed_password to POST /subscriptions/new."
      end

      rescue_from FeedCandidates::CredentialsInvalid do
        render_problem :unprocessable_content, "credentials_invalid",
          title: "Credentials invalid",
          detail: "The site refused that username and password."
      end

      def index
        data = serialize(subscriptions)
        return if not_modified?(etag_for("subscriptions", digest(data)))
        render_list(data)
      end

      def show
        render json: serialize([@subscription]).first
      end

      # GET, or POST when the feed needs credentials, which never go in a URL.
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
        return required_string("q") if request.post?

        %i[feed_username feed_password].each do |name|
          raise invalid_param(name, "invalid_value", "Send #{name} to POST /subscriptions/new, never in a URL.") if params.key?(name)
        end
        query = params[:q]
        raise invalid_param(:q, "missing", "q is required.") unless query.is_a?(String) && query.strip.present?
        raise invalid_param(:q, "invalid_value", "Send feed credentials to POST /subscriptions/new, never in a URL.") if FeedCandidates.credentials_in?(query)
        query.strip
      end

      def feed_credentials
        return {} unless request.post?
        {username: optional_string("feed_username"), password: optional_string("feed_password")}
      end

      def candidates_body(candidates, expand)
        list = {object: "list", data: candidates.map { FeedCandidateSerializer.new(it).to_h }}
        if expand.include?("tags")
          list[:tags] = TagList.new(@user).each_with_subscription_ids.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h }
        end
        list
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
