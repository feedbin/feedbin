module Api
  module V2
    class AuthenticationController < ApiController

      respond_to :json

      skip_before_action :valid_user

      def index
        expires_now
        render nothing: true
      end

    end
  end
end