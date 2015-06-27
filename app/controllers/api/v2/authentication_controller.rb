module Api
  module V2
    class AuthenticationController < ApiController

      skip_before_action :authorize

      respond_to :json

      def index
        expires_now

        user = authenticate_with_http_basic do |username, password|
          User.where('lower(email) = ?', username.try(:downcase)).take.try(:authenticate, password)
        end

        if user.present?
          render nothing: true
        else
          render json: {errors: ["Invalid email or password"]}, status: :unauthorized
        end

      end

    end
  end
end