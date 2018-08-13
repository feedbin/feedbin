module Api
  module V1
    class ApiController < ApplicationController
      skip_before_action :verify_authenticity_token

      def gone
        message = "Feedbin API V1 is no longer available. Please upgrade to V2: https://github.com/feedbin/feedbin-api#readme"
        render json: {status: 410, message: message}.to_json, status: :gone
      end
    end
  end
end
