module Api
  module V2
    class IconsController < ApiController
      respond_to :json

      def index
        @user = current_user
        feed_ids = @user.subscriptions.pluck(:feed_id)
        hosts = Feed.where(id: feed_ids).pluck(:host)
        @favicons = Favicon.where(host: hosts)
      end
    end
  end
end
