# Bearer tokens issued by Doorkeeper, and nothing else: v3 never takes the
# account password, not even as HTTP Basic auth. Sets @user and @token, then
# checks the account may use v3 at all.
module Api
  module V3
    module Authentication
      extend ActiveSupport::Concern
      include ActionController::HttpAuthentication::Token::ControllerMethods

      LAST_USED_RESOLUTION = 5.minutes

      included do
        before_action :authenticate
        before_action :authorize_account
      end

      private

      def authenticate
        @user = authenticate_with_http_token { |token, _options| user_for_token(token) }
        status_unauthorized unless @user
      end

      def user_for_token(plaintext)
        token = Doorkeeper::AccessToken.by_token(plaintext)
        return unless token&.accessible?

        @token = token
        token.update_column(:last_used_at, Time.now) unless token.last_used_at&.after?(LAST_USED_RESOLUTION.ago)
        User.includes(:plan).find_by(id: token.resource_owner_id)
      end

      def authorize_account
        ErrorService.context(user_id: @user.id)

        if !@user.api_v3_enabled? || @user.suspended || @user.plan.restricted?
          render_problem :forbidden, "restricted",
            title: "Restricted",
            detail: "This account does not have access to the API."
        end
      end

      def status_unauthorized
        challenge = %(Bearer realm="Feedbin")
        challenge += %(, error="invalid_token") if ActionController::HttpAuthentication::Token.token_and_options(request)
        response.headers["WWW-Authenticate"] = challenge
        render_problem :unauthorized, "unauthorized",
          title: "Unauthorized",
          detail: "The access token is missing or has been revoked."
      end
    end
  end
end
