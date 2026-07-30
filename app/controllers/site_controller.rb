class SiteController < ApplicationController
  skip_before_action :authorize, only: [:index, :manifest, :service_worker, :auto_sign_in]
  skip_before_action :verify_authenticity_token, only: [:service_worker]
  # `check_user` bounces a suspended session to billing, and as a before_action it
  # would run before auto_sign_in ever did — so signing in as a different account
  # from a suspended one appeared to do nothing at all.
  before_action :check_user, if: :signed_in?, except: [:auto_sign_in]

  def index
    if signed_in?
      clear_location
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
    @color = Colors.fetch(params[:theme])
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

    render formats: :json, content_type: "application/manifest+json"
  end

  # Development only, routed under a Rails.env.development? constraint. `email` or
  # `id` picks a specific account, which is what makes it possible to move between
  # test accounts while working on billing. A miss renders 404 rather than falling
  # back to User.first, so a typo can't quietly leave you as the wrong user.
  def auto_sign_in
    user = if params[:email].present?
      User.find_by_email(params[:email])
    elsif params[:id].present?
      User.find_by_id(params[:id])
    else
      User.first
    end

    return render_404 if user.nil?

    sign_in user
    redirect_to destination
  end

  private

  # `path` saves a hop when the account being signed in as is only interesting on
  # one page — a suspended one lands on billing anyway. Relative paths only, so
  # this stays a convenience and not an open redirect.
  def destination
    path = params[:path].to_s
    path.start_with?("/") ? path : root_url
  end

  def check_user
    if current_user.suspended && !native?
      redirect_to settings_billing_url, alert: "Please update your billing information to use Feedbin."
    elsif current_user.plan.restricted? && !native?
      redirect_to settings_url, alert: "Your subscription does not currently include web access."
    end
  end
end
