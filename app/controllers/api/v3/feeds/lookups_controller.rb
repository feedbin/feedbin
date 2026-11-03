module Api
  module V3
    module Feeds
      # GET /feeds/lookup: any feed Feedbin can reach (FeedLookup), with its
      # entries newest published first. It takes no token: the feed URL is
      # the credential, so it is throttled by address instead.
      class LookupsController < ApiController
        skip_before_action :authenticate, :authorize_account
        before_action :throttle

        MAX_IDS = 100
        MAX_ENTRIES = 5_000
        PER_HOUR = 120

        def show
          url = params[:url].to_s.strip
          raise invalid_param(:url, "missing", "url is required.") if url.empty?
          ids = id_list(:ids, max: MAX_IDS, of: "entry ids")
          changed_after = time_param(:changed_after)

          feed = FeedLookup.find(url) or return status_not_found
          entries = lookup_entries(feed, ids, changed_after)
          render json: FeedSerializer.new(feed).to_h.merge(entries: entries.map { EntrySerializer.new(_1).to_h })
        end

        private

        def lookup_entries(feed, ids, changed_after)
          scope = feed.entries
          scope = scope.where(id: ids) if ids
          scope = scope.where("entries.created_at > :time OR entries.edited_at > :time", time: changed_after) if changed_after
          scope.for_api_v3.order(published: :desc, id: :desc).limit(MAX_ENTRIES)
        end

        def throttle
          return if Throttle.throttle!("v3:feeds:lookup:#{request.remote_ip}", PER_HOUR, 1.hour)
          status_rate_limited(retry_after: 1.hour, detail: "Too many lookups from this address. Try again in an hour.")
        end
      end
    end
  end
end
