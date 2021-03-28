class SiteController < ApplicationController
  skip_before_action :authorize, only: [:index, :manifest, :service_worker]
  skip_before_action :verify_authenticity_token, only: [:service_worker]
  before_action :check_user, if: :signed_in?

  def index
    if signed_in?
      logged_in
    else
      render_file_or("home/index.html", :ok) {
        redirect_to login_url
      }
    end
  end

  def subscribe
    redirect_to root_url(request.query_parameters)
  end

  def service_worker
  end

  def manifest
    theme_options = {
      "day" => "#FFFFFF",
      "sunset" => "#f5f2eb",
      "dusk" => "#262626",
      "midnight" => "#000000"
    }
    @color = theme_options.fetch(params[:theme], theme_options["day"])
    @icons = [
      {
        src: helpers.asset_url("icon-manifest.png"),
        sizes: "192x192",
        type: "image/png",
        purpose: "maskable"
      },
      {
        src: helpers.asset_url("icon-manifest-large.png"),
        sizes: "512x512",
        type: "image/png",
        purpose: "any"
      }
    ]
    respond_to do |format|
      format.any {render "manifest.json.jbuilder", content_type: "application/manifest+json" }
    end
  end

  private

  def check_user
    if current_user.suspended && !native?
      redirect_to settings_billing_url, alert: "Please update your billing information to use Feedbin."
    end
  end
end
