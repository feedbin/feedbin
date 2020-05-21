class SiteController < ApplicationController
  skip_before_action :authorize, only: [:index]
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

  def headers
    @user = current_user
    if @user.admin?
      @headers = request.env.select { |k, v| k =~ /^HTTP_/ }
    end
  end

  private

  def check_user
    if current_user.suspended
      redirect_to settings_billing_url, alert: "Please update your billing information to use Feedbin."
    end
  end
end
