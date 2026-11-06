module Api
  module V3
    module Expansion
      extend ActiveSupport::Concern

      private

      def expansions(allowed)
        @expansions ||= begin
          names = params[:expand].to_s.split(",").map(&:strip).reject(&:empty?).uniq
          unknown = names - allowed
          if unknown.any?
            raise invalid_param(:expand, "invalid_value", "expand must be a comma-separated list of #{allowed.join(", ")}.")
          end
          names
        end
      end

      # memberships: {entry id => membership hash}
      def serialize_entries(entries, memberships: {})
        expand = expansions(EntrySerializer::EXPANSIONS)
        feeds = expand.include?("feed") ? serialize_feeds(entries.map(&:feed)) : {}
        videos = VideoLoader.call(entries)
        entries.map { EntrySerializer.new(_1, feed: feeds[_1.feed_id], expand: expand, membership: memberships[_1.id], videos: videos[_1.id]).to_h }
      end

      # {feed id => feed object}
      def serialize_feeds(feeds)
        feeds.uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] }
      end
    end
  end
end
