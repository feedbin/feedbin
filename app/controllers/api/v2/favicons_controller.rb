module Api
  module V2
    class FaviconsController < ApiController
      respond_to :json
      skip_before_action :valid_user

      # Retired with the base64 favicons column. The route stays so a client
      # that still calls it sees an empty list rather than a 404.
      def index
        render json: []
      end
    end
  end
end
