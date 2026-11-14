# Revoking an app under Authorized Apps signs the user out of it everywhere.
# Not behind the API v3 setting: access granted earlier can always be revoked.
class Settings::ApiAuthorizationsController < ApplicationController
  def destroy
    @user.oauth_access_tokens.sign_ins.where(application_id: params[:id]).find_each(&:revoke)
    redirect_to settings_account_path, notice: "Access revoked."
  end
end
