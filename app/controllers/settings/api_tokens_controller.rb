class Settings::ApiTokensController < ApplicationController
  before_action :require_api_v3

  # A token for the user's own account, created without the OAuth flow, for
  # pasting into a client or a script.
  def create
    application = @user.oauth_applications.find(params[:api_application_id])
    # Feedbin's own apps sign in through OAuth, which is what gives them the
    # account scope; a settings token would have only read write and still
    # fail on push, purchases and the account.
    if application.scopes.include?("account")
      return redirect_to settings_api_application_path(application), alert: "Tokens for Feedbin's own apps come from signing in to the app."
    end
    token = application.access_tokens.create!(
      resource_owner_id: @user.id,
      device_name: params.dig(:token, :device_name).presence,
      scopes: Api::V3::Scopes::DEFAULT
    )
    flash[:plaintext_token] = token.plaintext_token
    redirect_to settings_api_application_path(application), notice: "Token created."
  end

  # Revokes any of the user's tokens, including ones granted to someone
  # else's app through OAuth.
  def destroy
    token = @user.oauth_access_tokens.where(application_id: params[:api_application_id]).find(params[:id])
    token.revoke
    redirect_back fallback_location: settings_api_applications_path, notice: "Token revoked."
  end
end
