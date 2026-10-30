class Settings::ApiApplicationsController < ApplicationController
  layout "settings"

  before_action :require_api_v3

  def index
    render Settings::ApiApplications::IndexView.new(user: @user)
  end

  def new
    render Settings::ApiApplications::NewView.new(application: @user.oauth_applications.new)
  end

  def create
    application = @user.oauth_applications.new(application_params)
    if application.save
      # Secrets are stored hashed, so this is the only time the plaintext
      # exists. It survives the redirect in the encrypted session cookie.
      flash[:plaintext_secret] = application.plaintext_secret if application.confidential?
      redirect_to settings_api_application_path(application), notice: "Application created."
    else
      render Settings::ApiApplications::NewView.new(application: application), status: :unprocessable_content
    end
  end

  def show
    application = @user.oauth_applications.find(params[:id])
    render Settings::ApiApplications::ShowView.new(
      user: @user,
      application: application,
      plaintext_secret: flash[:plaintext_secret],
      plaintext_token: flash[:plaintext_token]
    )
  end

  def destroy
    @user.oauth_applications.find(params[:id]).destroy
    redirect_to settings_api_applications_path, notice: "Application deleted."
  end

  private

  def application_params
    params.expect(doorkeeper_application: [:name, :redirect_uri, :confidential])
  end
end
