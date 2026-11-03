# Loads @feed for a feed the user can read (FeedList). One that exists but
# isn't readable is 403 not_readable; one that doesn't exist is 404.
module Api
  module V3
    module FeedScoped
      extend ActiveSupport::Concern

      private

      def set_feed
        @feed = Feed.find(params[:feed_id] || params[:id])
        return if FeedList.new(@user).include?(@feed)
        render_problem :forbidden, "not_readable",
          title: "Not readable",
          detail: "The feed exists but this account cannot read it."
      end
    end
  end
end
