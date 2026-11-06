module Api
  module V3
    class FeedsController < ApiController
      include FeedScoped

      before_action :set_feed, only: :show

      def index
        list = FeedList.new(@user)
        return if not_modified?(etag_for("feeds", list.version))
        render_list(list.feeds.includes(*Feed::ICON_PRELOADS, :touch_icon_image_record).order(:id).map { FeedSerializer.new(_1).to_h })
      end

      def show
        render json: FeedSerializer.new(@feed).to_h
      end
    end
  end
end
