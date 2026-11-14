class Settings::ApiApplicationLogosController < ApplicationController
  before_action :require_api_v3
  before_action :set_application

  def create
    if params[:logo].respond_to?(:path) && Api::V3::ApplicationLogo.replace(@application, params[:logo])
      redirect_to settings_api_application_path(@application), notice: "Logo updated."
    else
      redirect_to settings_api_application_path(@application), alert: "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB."
    end
  end

  def destroy
    Api::V3::ApplicationLogo.for(@application)&.destroy
    redirect_to settings_api_application_path(@application), notice: "Logo removed."
  end

  private

  def set_application
    @application = @user.oauth_applications.find(params[:api_application_id])
  end
end
