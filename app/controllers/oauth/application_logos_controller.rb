# Public: the authorize page shows it to signed-out visitors.
class Oauth::ApplicationLogosController < Oauth::BaseController
  def show
    application = Doorkeeper::Application.find_by!(uid: params[:uid])
    profile = Api::V3::ApplicationProfile.where.not(logo: nil).find_by!(application_id: application.id)

    # The URL carries the logo's version, so a cached copy is never stale.
    expires_in 1.year, public: true
    send_data profile.logo, type: "image/png", disposition: "inline"
  end
end
