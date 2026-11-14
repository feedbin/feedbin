# Removes an application's logo. Uploading one is part of the edit form.
class Settings::ApiApplicationLogosController < ApplicationController
  before_action :require_api_v3
  before_action :set_application

  def destroy
    Api::V3::ApplicationLogo.for(@application)&.destroy
    redirect_to edit_settings_api_application_path(@application), notice: "Logo removed."
  end

  private

  def set_application
    @application = @user.oauth_applications.find(params[:api_application_id])
  end
end
