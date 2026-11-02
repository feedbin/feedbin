# OAuth2 provider for API v3. Apps are registered in Settings > API and are
# owned by the user who registered them. The flows are authorization code with
# PKCE, for third-party apps, and tokens created directly in settings.
Doorkeeper.configure do
  orm :active_record

  # Inheriting ApplicationController brings its sign-in redirect, so a
  # signed-out visitor to /oauth/authorize is sent to the login form and back.
  base_controller "ApplicationController"

  resource_owner_authenticator do
    require_api_v3
    current_user unless performed?
  end

  enable_application_owner confirmation: true

  # read and write for every token; account only for Feedbin's own apps,
  # whose registered scopes include it. Whatever a client asks for is
  # replaced (see Api::V3::Scopes and the authorizations filter below).
  default_scopes :read, :write
  optional_scopes :account
  enforce_configured_scopes

  grant_flows %w[authorization_code]
  force_pkce
  pkce_code_challenge_methods %w[S256]

  # Tokens last until revoked, as in the v3 spec: a client gets one token
  # once and keeps it.
  access_token_expires_in nil
  authorization_code_expires_in 10.minutes

  hash_token_secrets
  hash_application_secrets

  access_token_generator "Api::V3::TokenGenerator"

  # An app that only holds tokens created in settings never redirects.
  allow_blank_redirect_uri true

  # Native apps redirect to custom schemes, and loopback redirects are http.
  force_ssl_in_redirect_uri { |uri| !%w[localhost 127.0.0.1 [::1]].include?(uri.host) }

  allow_token_introspection false
  realm "Feedbin"
end

Rails.application.config.to_prepare do
  # The authorization views render inside layouts/form_page themselves, the
  # same way the sign-in form does.
  Doorkeeper::AuthorizationsController.layout false

  Doorkeeper::AuthorizationsController.class_eval do
    before_action :assign_v3_scopes, only: [:new, :create]

    private

    # A third party cannot choose its scopes, and Feedbin's apps need not ask.
    def assign_v3_scopes
      application = Doorkeeper::Application.by_uid(params[:client_id].to_s)
      params[:scope] = Api::V3::Scopes.for(application) if application
    end
  end
end
