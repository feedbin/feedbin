module Api
  module V3
    class FeedsController < ApiController
      include FeedScoped

      before_action :set_feed, only: :show

      def index
        list = FeedList.new(@user)
        return index_with_counts(list) if expansions(FeedSerializer::EXPANSIONS).include?("daily_entry_counts")
        return unless stale?(etag: list.version)
        render_list(listed_feeds(list).map { FeedSerializer.new(_1).to_h })
      end

      def show
        render json: FeedSerializer.new(@feed, candidate: expanded_fields).to_h
      end

      private

      def listed_feeds(list)
        list.feeds.includes(*Feed::ICON_PRELOADS, :touch_icon_image_record).order(:id).to_a
      end

      # The counts move as feeds publish, not when the list does, so the ETag is the body's.
      def index_with_counts(list)
        feeds = listed_feeds(list)
        counts = FeedStat.daily_counts(feed_ids: feeds.map(&:id), interval: FeedStat::API_INTERVAL)
        data = feeds.map { FeedSerializer.new(_1, candidate: {daily_entry_counts: counts[_1.id]&.counts || []}).to_h }
        return unless stale?(etag: digest(data))
        render_list(data)
      end

      def expanded_fields
        {daily_entry_counts: @feed.daily_entry_counts} if expansions(FeedSerializer::EXPANSIONS).include?("daily_entry_counts")
      end
    end
  end
end
