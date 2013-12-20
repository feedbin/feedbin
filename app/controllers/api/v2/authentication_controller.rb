module Api
  module V2
    class AuthenticationController < ApiController

      respond_to :json

      def index
        expires_now
        render nothing: true
      end

    end
  end
end