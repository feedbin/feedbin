class Settings::ApiTokensController < ApplicationController
  before_action :require_api_v3

  def create
    application = @user.oauth_applications.find(params[:api_application_id])
    device_name = params.dig(:token, :device_name).to_s.strip
    if device_name.empty?
      return redirect_to settings_api_application_path(application), alert: "Name the token so you can tell it apart later."
    end
    token = application.access_tokens.create!(
      resource_owner_id: @user.id,
      device_name: device_name,
      scopes: Api::V3::Scopes::DEFAULT
    )
    flash[:plaintext_token] = token.plaintext_token
    redirect_to settings_api_application_path(application), notice: "Token created."
  end

  def destroy
    token = @user.oauth_access_tokens.where(application_id: params[:api_application_id]).find(params[:id])
    token.revoke
    redirect_back fallback_location: settings_api_applications_path, notice: "Token revoked."
  end
end
