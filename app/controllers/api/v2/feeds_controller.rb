module Api
  module V2
    class FeedsController < ApiController
      before_action :correct_user

      respond_to :json

      def show
        @feed = Feed.find(params[:id])
        fresh_when(@feed)
      end

      private

      def correct_user
        unless current_user.can_read_feed?(params[:id])
          render_404
        end
      end
    end
  end
end
