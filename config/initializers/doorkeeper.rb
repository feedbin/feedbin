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

  # One scope for now: full access to the account. Narrower scopes, such as
  # read-only, can be added later as optional scopes without breaking clients.
  default_scopes :full

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
end
