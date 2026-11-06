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

  # Digital Asset Links: lets password managers on Android offer this site's
  # logins in the app. ANDROID_ASSET_LINKS lists package=sha256 pairs, comma
  # separated (a package can appear once per signing key). Unset, it answers
  # with an empty statement list, like apple_site_association.
  def android_asset_links
    fingerprints = ENV["ANDROID_ASSET_LINKS"].to_s.split(",").filter_map { |pair|
      package, fingerprint = pair.strip.split("=", 2)
      [package, fingerprint] if package.present? && fingerprint.present?
    }.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

    render json: fingerprints.map { |package, sha256s|
      {
        relation: ["delegate_permission/common.get_login_creds"],
        target: {namespace: "android_app", package_name: package, sha256_cert_fingerprints: sha256s}
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
