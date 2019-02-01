class WellKnownController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def apple_site_association
    render json: {
      "webcredentials": {
        "apps": ENV["APPLE_SITE_ASSOCIATION"].split(","),
      },
    }
  end

  def apple_pay
    render plain: ENV["APPLE_PAY_KEY"]
  end

  def change_password
    redirect_to settings_account_url, status: :moved_permanently
  end
end
