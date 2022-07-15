module Api
  module V2
    class AuthenticationController < ApiController
      respond_to :json

      def index
        expires_now
        head :ok
      end

      def valid_user
        if current_user.plan.restricted?
          status_forbidden
        end
      end
    end
  end
end
