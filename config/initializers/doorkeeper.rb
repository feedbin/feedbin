Doorkeeper.configure do
  orm :active_record

  # ApplicationController's sign-in redirect returns signed-out visitors here.
  base_controller "ApplicationController"

  resource_owner_authenticator do
    require_api_v3
    current_user unless performed?
  end

  enable_application_owner confirmation: true

  # Requested scopes are replaced by Api::V3::Scopes (see assign_v3_scopes below).
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

Rails.application.config.to_prepare do
  # The authorization views render layouts/form_page themselves.
  Doorkeeper::AuthorizationsController.layout false

  Doorkeeper::AuthorizationsController.class_eval do
    before_action :assign_v3_scopes, only: [:new, :create]

    private

    def assign_v3_scopes
      application = Doorkeeper::Application.by_uid(params[:client_id].to_s)
      params[:scope] = Api::V3::Scopes.for(application) if application
    end
  end
end
