module Api
  module V3
    # GET /feeds (the user's feeds and the feeds of their starred entries, with
    # an ETag), GET /feeds/{id}, GET /feeds/{id}/entries (one feed's timeline),
    # and GET /feeds/lookup, which takes no token: the feed URL is the credential.
    class FeedsController < ApiController
      include Timeline

      skip_before_action :authenticate, :authorize_account, only: :lookup
      before_action :throttle_lookup, only: :lookup

      LOOKUP_IDS = 100
      LOOKUP_ENTRIES = 5_000
      LOOKUPS_PER_HOUR = 120

      def index
        feeds = listed_feeds
        return if not_modified?(feeds_etag(feeds))

        feeds = feeds.includes(*Feed::ICON_PRELOADS, :touch_icon_image_record).order(:id)
        render_list(feeds.map { FeedSerializer.new(_1).to_h })
      end

      def show
        feed = readable_feed or return
        render json: FeedSerializer.new(feed).to_h
      end

      def entries
        readable_feed or return
        render_timeline
      end

      # Any feed Feedbin can reach, with its entries newest published first.
      # A known feed not fetched recently is refreshed first; an unknown URL
      # is discovered. Failures to reach the feed are "not found".
      def lookup
        url = params[:url].to_s.strip
        raise Problems::InvalidParameter.new("url is required.", pointer: "url", code: "missing") if url.empty?
        ids = lookup_ids
        changed_after = time_param(:changed_after)

        feed = Feed.xml.find_by(feed_url: url)
        if feed
          refresh(feed) if feed.standalone_request_at.blank? || feed.standalone_request_at.before?(StandaloneRetention::TTL.ago)
        else
          feed = discover(url)
        end
        return status_not_found unless feed

        feed.touch(:standalone_request_at)
        scope = feed.entries
        scope = scope.where(id: ids) if ids
        scope = scope.where("entries.created_at > :time OR entries.edited_at > :time", time: changed_after) if changed_after
        entries = scope.merge(with_associations).order(published: :desc, id: :desc).limit(LOOKUP_ENTRIES).to_a
        render json: FeedSerializer.new(feed).to_h.merge(entries: entries.map { EntrySerializer.new(_1).to_h })
      end

      private

      # Readable: subscribed, or a starred entry from the feed. Otherwise
      # 403 not_readable; a feed that does not exist is 404.
      def readable_feed
        @feed ||= begin
          feed = Feed.find(params[:id])
          unless @user.can_read_feed?(feed)
            render_problem :forbidden, "not_readable",
              title: "Not readable",
              detail: "The feed exists but this account cannot read it."
            return nil
          end
          feed
        end
      end

      def timeline_base
        @feed.entries
      end

      def streams?
        false
      end

      # Every feed the user can read: the ones they subscribe to and the ones
      # they have starred entries from, the same rule as readable_feed. A
      # relation over two subqueries, so the ETag and the list share it.
      def listed_feeds
        Feed.where(id: @user.subscriptions.select(:feed_id))
          .or(Feed.where(id: @user.starred_entries.select(:feed_id)))
      end

      # The set of feeds changes with the subscriptions list and the starred
      # list, and a feed's row changes whenever the crawler saves it, so the
      # two versions and the newest updated_at together move on every change a
      # client sees.
      def feeds_etag(feeds)
        newest = feeds.maximum(:updated_at)
        etag_for("feeds", versions.fetch("subscriptions"), versions.fetch("starred"), newest ? (newest.to_r * 1_000_000).to_i : 0)
      end

      def lookup_ids
        return nil unless params.key?(:ids)
        ids = params[:ids].to_s.split(",").map { Integer(_1.strip, exception: false) }
        raise Problems::InvalidParameter.new("ids must be comma-separated entry ids.", pointer: "ids", code: "invalid_value") if ids.empty? || ids.any?(&:nil?)
        raise Problems::InvalidParameter.new("ids takes at most #{LOOKUP_IDS} ids.", pointer: "ids", code: "too_many") if ids.size > LOOKUP_IDS
        ids
      end

      def refresh(feed)
        FeedStatus.new.perform(feed.id)
        FeedUpdate.new.perform(feed.id)
      rescue => exception
        ErrorService.notify(exception, context: {feed_id: feed.id})
      end

      def discover(url)
        FeedFinder.feeds(url).first
      rescue Feedkit::Error, HTTP::Error, Addressable::URI::InvalidURIError
        nil
      end

      def throttle_lookup
        return if Throttle.throttle!("v3:feeds:lookup:#{request.remote_ip}", LOOKUPS_PER_HOUR, 1.hour)
        response.set_header("Retry-After", 1.hour.to_i.to_s)
        render_problem :too_many_requests, "rate_limited",
          title: "Rate limited",
          detail: "Too many lookups from this address. Try again in an hour."
      end
    end
  end
end
