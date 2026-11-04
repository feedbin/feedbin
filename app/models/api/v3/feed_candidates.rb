module Api
  module V3
    # GET /subscriptions/new: the feeds a typed query offers the user, as the
    # web's add-feed dialog finds them. A URL is fetched and its feeds
    # discovered; words search known feeds. Either way the result is a list,
    # every feed in it is offered (Subscribe.offer) and refreshed, and nothing
    # is subscribed.
    class FeedCandidates
      class CredentialsRequired < StandardError; end
      class CredentialsInvalid < StandardError; end

      Candidate = Data.define(:feed, :subscription, :daily_entry_counts)

      # As ApplicationController#looks_like_url?.
      def self.url?(query)
        query.start_with?("http") || (query.include?(".") && !query.include?(" "))
      end

      # user:pass@ in the authority, which Feedkit would send.
      def self.credentials_in?(query)
        Feedkit::BasicAuth.parse(query).username.present?
      end

      def initialize(user, query, username: nil, password: nil)
        @user = user
        @query = query
        @username = username.presence
        @password = password.presence
      end

      # => [Candidate]
      def candidates
        @candidates ||= begin
          feeds = found
          preload(feeds)
          existing = @user.existing_subscriptions(feeds)
          stats = FeedStat.daily_counts(feed_ids: feeds.map(&:id))
          Subscribe.offer(@user, feeds)
          feeds.each { it.priority_refresh(@user) }
          feeds.map { Candidate.new(it, existing[it.id] || existing[it.feed_url], stats[it.id]&.counts || []) }
        end
      end

      private

      def found
        (self.class.url?(@query) ? discover : search).uniq(&:id)
      end

      # Any failure finds nothing, as FeedLookup.discover's do, except a site
      # that asks for a password.
      def discover
        FeedFinder.feeds(@query, username: @username, password: @password).to_a
      rescue Feedkit::Unauthorized => exception
        return [] unless exception.basic_auth?
        raise credentials_sent? ? CredentialsInvalid : CredentialsRequired
      rescue Feedkit::Error, HTTP::Error, Addressable::URI::InvalidURIError
        []
      rescue => exception
        ErrorService.notify(exception)
        []
      end

      def search
        Feed.search(@query).to_a
      rescue => exception
        ErrorService.notify(exception)
        []
      end

      def credentials_sent?
        @username || @password || self.class.credentials_in?(@query)
      end

      def preload(feeds)
        ActiveRecord::Associations::Preloader.new(records: feeds, associations: [*Feed::ICON_PRELOADS, :touch_icon_image_record]).call
      end
    end
  end
end
