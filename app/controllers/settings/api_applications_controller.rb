class Settings::ApiApplicationsController < ApplicationController
  layout "settings"

  before_action :require_api_v3
  before_action :build_application, only: [:new, :create]
  before_action :set_application, only: [:show, :edit, :update]
  before_action :set_profile, except: :index

  def index
    render Settings::ApiApplications::IndexView.new(user: @user)
  end

  def new
    render Settings::ApiApplications::NewView.new(application: @application, profile: @profile)
  end

  def create
    if save_application
      redirect_to settings_api_application_path(@application), notice: "Application created."
    else
      render Settings::ApiApplications::NewView.new(application: @application, profile: @profile), status: :unprocessable_content
    end
  end

  def show
    render Settings::ApiApplications::ShowView.new(
      user: @user,
      application: @application,
      profile: @profile,
      plaintext_token: flash[:plaintext_token]
    )
  end

  def edit
    render Settings::ApiApplications::EditView.new(application: @application, profile: @profile)
  end

  # Tokens belong to the application's id, so they survive a rename or new
  # redirect URIs.
  def update
    if save_application
      redirect_to settings_api_application_path(@application), notice: "Application updated."
    else
      render Settings::ApiApplications::EditView.new(application: @application, profile: @profile), status: :unprocessable_content
    end
  end

  private

  def build_application
    @application = @user.oauth_applications.new
  end

  def set_application
    @application = @user.oauth_applications.find(params[:id])
  end

  def set_profile
    @profile = Api::V3::ApplicationProfile.for(@application)
  end

  def save_application
    @application.assign_attributes(application_params)
    @profile.assign_attributes(profile_params)
    @profile.save_with(@application)
  end

  # Every application is a public client: PKCE is required, and there is no
  # client secret.
  def application_params
    params.expect(doorkeeper_application: [:name, :redirect_uri])
  end

  # logo_file is an upload, which becomes the logo.
  def profile_params
    params.fetch(:profile, {}).permit(:description, :url, :contact_email, :logo_file)
  end
end
