module Api
  module V3
    class FeedsController < ApiController
      include FeedScoped

      before_action :set_feed, only: :show

      def index
        list = FeedList.new(@user)
        return unless stale?(etag: list.version)
        render_list(list.feeds.includes(*Feed::ICON_PRELOADS, :touch_icon_image_record).order(:id).map { FeedSerializer.new(_1).to_h })
      end

      def show
        render json: FeedSerializer.new(@feed, candidate: expanded_fields).to_h
      end

      private

      def expanded_fields
        {daily_entry_counts: @feed.daily_entry_counts} if expansions(FeedSerializer::EXPANSIONS).include?("daily_entry_counts")
      end
    end
  end
end
