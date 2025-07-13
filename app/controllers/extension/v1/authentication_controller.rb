module Extension
  module V1
    class AuthenticationController < ApiController
      skip_before_action :authorize, only: [:options]

      def index
      end
    end
  end
end