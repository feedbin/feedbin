class WellKnownController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def apple_site_association
    render json: {
      "webcredentials": {
        # A deployment without the variable set answers with a well-formed
        # association claiming no apps, the way apple_pay below answers with an
        # empty body -- rather than putting a NoMethodError on an
        # unauthenticated, crawler-reachable route.
        "apps": ENV["APPLE_SITE_ASSOCIATION"].to_s.split(",")
      }
    }
  end

  def apple_pay
    render plain: ENV["APPLE_PAY_KEY"]
  end

  def change_password
    redirect_to settings_account_url, status: :moved_permanently
  end
end
