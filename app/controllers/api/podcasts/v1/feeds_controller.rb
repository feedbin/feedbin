module Api
  module Podcasts
    module V1
      class FeedsController < ApiController
        skip_before_action :authorize
        skip_before_action :set_user
        before_action :parse_updated_since
        before_action :parse_ids

        MAX_IDS = 100

        class_attribute :max_items, default: 5_000, instance_accessor: false

        def show
          url = hex_decode(params[:id])
          @feed = Feed.xml.find_by_feed_url(url)
          if @feed.present?
            if @feed.standalone_request_at.blank? || @feed.standalone_request_at.before?(StandaloneRetention::TTL.ago)
              FeedStatus.new.perform(@feed.id)
              FeedUpdate.new.perform(@feed.id)
            end
          else
            feeds = FeedFinder.feeds(url)
            @feed = feeds.first
          end

          if @feed.present?
            @feed.touch(:standalone_request_at)
            @entries = entries.order(published: :desc).limit(self.class.max_items).load
            Librato.increment "podcast.feeds.show", source: source
            Librato.measure "podcast.feeds.items", @entries.size, source: source
          else
            status_not_found
          end
        rescue => exception
          if Rails.env.production?
            ErrorService.notify(exception)
            status_not_found
          else
            raise exception
          end
        end

        private

        def entries
          if @ids.present?
            @feed.entries.where(id: @ids)
          elsif @updated_since
            @feed.entries.where("entries.updated_at > ?", @updated_since)
          else
            @feed.entries
          end
        end

        # Parsed before the action so a bad value is a 400. 
        def parse_updated_since
          return if params[:updated_since].blank?
          @updated_since = Time.zone.iso8601(params[:updated_since])
        rescue ArgumentError, TypeError
          status_bad_request([{updated_since: "Invalid ISO 8601 timestamp"}])
        end

        # Scoped to this feed on purpose. Entry ids are sequential and this
        # endpoint is unauthenticated, so an id lookup that reached across
        # The feed URL is the credential — a private feed's URL carries its
        # secret — and an id from another feed yields nothing here.
        def parse_ids
          return unless params.key?(:ids)
          unless params[:ids].is_a?(String)
            return status_bad_request([{ids: "Please pass ids as a comma-separated string"}])
          end
          @ids = params[:ids].split(",").map(&:to_i)
          if @ids.size > MAX_IDS
            status_bad_request([{ids: "Please request less than or equal to #{MAX_IDS} ids per request"}])
          end
        end

        # Which shape of request this was, for sizing the delta once clients
        # send it: how many requests of each kind, and how many items each
        # carried.
        def source
          if @ids.present?
            "ids"
          elsif @updated_since
            "delta"
          else
            "full"
          end
        end
      end
    end
  end
end
