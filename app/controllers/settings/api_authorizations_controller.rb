# Revoking an app under Authorized Apps signs the user out of it everywhere.
class Settings::ApiAuthorizationsController < ApplicationController
  before_action :require_api_v3

  def destroy
    @user.oauth_access_tokens.sign_ins.where(application_id: params[:id]).find_each(&:revoke)
    redirect_to settings_api_applications_path, notice: "Access revoked."
  end
end
