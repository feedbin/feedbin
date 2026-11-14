class Settings::ApiApplicationsController < ApplicationController
  layout "settings"

  before_action :require_api_v3
  before_action :set_application, only: [:show, :edit, :update]

  def index
    render Settings::ApiApplications::IndexView.new(user: @user)
  end

  def new
    render Settings::ApiApplications::NewView.new(application: @user.oauth_applications.new)
  end

  def create
    @application = @user.oauth_applications.new
    if save_application
      redirect_to settings_api_application_path(@application), notice: "Application created."
    else
      render Settings::ApiApplications::NewView.new(application: @application), status: :unprocessable_content
    end
  end

  def show
    render Settings::ApiApplications::ShowView.new(
      user: @user,
      application: @application,
      plaintext_token: flash[:plaintext_token]
    )
  end

  def edit
    render Settings::ApiApplications::EditView.new(application: @application)
  end

  # Tokens belong to the application's id, so they survive a rename or new
  # redirect URIs.
  def update
    if save_application
      redirect_to settings_api_application_path(@application), notice: "Application updated."
    else
      render Settings::ApiApplications::EditView.new(application: @application), status: :unprocessable_content
    end
  end

  private

  def set_application
    @application = @user.oauth_applications.find(params[:id])
  end

  # The logo is saved with the fields or not at all.
  def save_application
    Doorkeeper::Application.transaction do
      @application.update(application_params) && save_logo or raise ActiveRecord::Rollback
    end
  end

  def save_logo
    return true unless params[:logo].respond_to?(:path)
    return true if Api::V3::ApplicationLogo.replace(@application, params[:logo])

    @application.errors.add(:base, "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB")
    false
  end

  # Every application is a public client: PKCE is required, and there is no
  # client secret.
  def application_params
    params.expect(doorkeeper_application: [:name, :redirect_uri])
  end
end
