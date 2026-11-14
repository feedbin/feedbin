# Doorkeeper bearer tokens only: v3 never accepts the account password.
# Doorkeeper finds the token, checks it and its scopes, and answers a failure
# itself with the status and WWW-Authenticate header; only the body is ours.
module Api
  module V3
    module Authentication
      extend ActiveSupport::Concern

      LAST_USED_RESOLUTION = 5.minutes

      included do
        before_action :authenticate
        before_action :authorize_account
      end

      private

      # With no scope named, Doorkeeper asks for one of its defaults: read or write.
      def authenticate
        doorkeeper_authorize!
        return if performed?

        @token = doorkeeper_token
        @token.update_column(:last_used_at, Time.now) unless @token.last_used_at&.after?(LAST_USED_RESOLUTION.ago)
        # Tokens are deleted with their user, so a token has one.
        @user = User.includes(:plan).find(@token.resource_owner_id)
      end

      def authorize_account
        ErrorService.context(user_id: @user.id)

        if !@user.api_v3_enabled? || (!lapsed_account_allowed? && (@user.suspended || @user.plan.restricted?))
          render_problem :forbidden, "restricted",
            title: "Restricted",
            detail: "This account does not have access to the API."
        end
      end

      # Overridden where a suspended or restricted account may still act.
      def lapsed_account_allowed?
        false
      end

      def doorkeeper_unauthorized_render_options(**)
        problem_render_options :unauthorized, "unauthorized",
          title: "Unauthorized",
          detail: "The access token is missing or has been revoked."
      end

      def doorkeeper_forbidden_render_options(**)
        detail = if @_doorkeeper_scopes.map(&:to_s) == ["account"]
          "This needs the account scope, which only Feedbin's apps have."
        else
          "This needs the #{@_doorkeeper_scopes.to_a.join(" or ")} scope."
        end
        problem_render_options :forbidden, "insufficient_scope", title: "Insufficient scope", detail: detail
      end
    end
  end
end
