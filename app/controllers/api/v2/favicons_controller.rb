module Api
  module V2
    class FaviconsController < ApiController

      respond_to :json
      skip_before_action :valid_user

      def index
        @user = current_user
        feed_ids = @user.subscriptions.pluck(:feed_id)
        hosts = Feed.where(id: feed_ids).pluck(:host)
        @favicons = Favicon.where(host: hosts).unscoped
        fresh_when(@favicons)
      end

    end
  end
end