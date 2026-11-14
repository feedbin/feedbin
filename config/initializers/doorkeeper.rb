Doorkeeper.configure do
  orm :active_record

  # Skips ApplicationController's sign-in redirect: the authorize page signs
  # visitors in itself, and renders layouts/oauth_page from its own views.
  base_controller "Oauth::BaseController"

  resource_owner_authenticator { oauth_resource_owner }

  enable_application_owner confirmation: true

  # Requested scopes are replaced by Api::V3::Scopes (see Oauth::BaseController).
  default_scopes :read, :write
  optional_scopes :account
  enforce_configured_scopes

  grant_flows %w[authorization_code]
  force_pkce
  pkce_code_challenge_methods %w[S256]

  access_token_expires_in nil
  authorization_code_expires_in 10.minutes

  hash_token_secrets
  hash_application_secrets

  access_token_generator "Api::V3::TokenGenerator"

  # An app that only holds tokens created in settings never redirects.
  allow_blank_redirect_uri true

  # Native apps use custom schemes; loopback redirects are http.
  force_ssl_in_redirect_uri { |uri| !%w[localhost 127.0.0.1 [::1]].include?(uri.host) }

  allow_token_introspection false
  realm "Feedbin"
end
