module Api
  module V3
    # One row of GET /subscriptions/new: the feed object unchanged, the user's
    # subscription to it (or to a feed that redirected to it), and 30 daily
    # entry counts, oldest first, for the sparkline. A part of a response,
    # not a record, so it has no id or object.
    class FeedCandidateSerializer
      def initialize(candidate)
        @candidate = candidate
      end

      def to_h
        {
          feed: FeedSerializer.new(@candidate.feed).to_h,
          subscription_id: @candidate.subscription&.id,
          daily_entry_counts: @candidate.daily_entry_counts
        }
      end
    end
  end
end
