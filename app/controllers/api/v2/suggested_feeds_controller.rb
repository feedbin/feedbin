module Api
  module V2
    class SuggestedFeedsController < ApiController

      respond_to :json

      skip_before_action :authorize, only: [:index]

      def index
        @suggested_feeds = SuggestedFeed.limit(200).includes(:feed)
      end

    end
  end
end
