module Api
  module V2
    class FeedsController < ApiController

      respond_to :json

      def show
        @feed = Feed.find(params[:id])
        fresh_when(@feed)
      end

    end
  end
end