module Api
  module V3
    # POST /subscriptions/new: the feeds a typed query offers the user, as the
    # web's add-feed dialog finds them. A URL is fetched and its feeds
    # discovered; words search known feeds. Either way the result is a list,
    # every feed in it is offered (Subscribe.offer) and refreshed, and nothing
    # is subscribed. Finding nothing is a Failure that says why, for the
    # client to show.
    class FeedCandidates
      # code is the problem's code; detail is a sentence a client can show.
      # http_code is the site's status, for upstream_error.
      class Failure < StandardError
        attr_reader :code, :title, :http_code

        def initialize(code, title, detail, http_code: nil)
          super(detail)
          @code = code
          @title = title
          @http_code = http_code
        end
      end

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
        feeds = (self.class.url?(@query) ? discover : search).uniq(&:id)
        raise failure(:no_feed_found, search_detail) if feeds.empty? && !self.class.url?(@query)
        feeds
      end

      # Feedkit's errors, grouped by what the user can do about them. Raised
      # from a rescue clause, a Failure skips the clauses after it. Anything
      # unexpected stays a 500.
      def discover
        finder = FeedFinder.new(@query, username: @username, password: @password, raise_errors: true)
        feeds = finder.find
        raise empty_page(finder.response) if feeds.empty?
        feeds
      rescue Feedkit::Unauthorized => exception
        raise credentials_failure if exception.basic_auth?
        raise upstream_error(exception)
      rescue Feedkit::ResponseError => exception
        raise upstream_error(exception)
      rescue Feedkit::InvalidUrl, Addressable::URI::InvalidURIError
        raise failure(:invalid_url, "That address isn’t valid.")
      rescue Feedkit::NotFeed, Feedkit::NotSupported, Feedkit::TooLarge
        raise not_a_feed
      rescue Feedkit::Error, HTTP::Error
        raise failure(:unreachable, "Couldn’t connect to #{host}.")
      end

      def search
        Feed.search(@query).to_a
      end

      # The page loaded and no source found a feed: markup (HTML, or a feed
      # that could not be saved) has no feed; anything else is not a feed.
      def empty_page(response)
        parsed = response&.parse(validate: false)
        parsed ? failure(:no_feed_found, "This page doesn’t have a feed.") : not_a_feed
      rescue Feedkit::Error
        not_a_feed
      end

      def not_a_feed
        failure(:not_a_feed, "This link isn’t a feed or a web page.")
      end

      def upstream_error(exception)
        code = exception.response&.code
        Failure.new("upstream_error", "Upstream error", "#{host} returned an error (#{code}).", http_code: code)
      end

      def credentials_failure
        if credentials_sent?
          failure(:credentials_invalid, "The site refused that username and password.")
        else
          failure(:credentials_required, "The site needs a username and password. Send them as feed_username and feed_password to POST /subscriptions/new.")
        end
      end

      TITLES = {
        no_feed_found: "No feed found",
        not_a_feed: "Not a feed",
        unreachable: "Unreachable",
        invalid_url: "Invalid URL",
        credentials_required: "Credentials required",
        credentials_invalid: "Credentials invalid"
      }.freeze

      def failure(code, detail)
        Failure.new(code.to_s, TITLES.fetch(code), detail)
      end

      def search_detail
        "No feeds match “#{@query}”. Try the site’s address."
      end

      def host
        Addressable::URI.heuristic_parse(Feedkit::BasicAuth.parse(@query).url).host || @query
      rescue Addressable::URI::InvalidURIError
        @query
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
