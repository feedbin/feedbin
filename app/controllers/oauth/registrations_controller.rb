# Creating an account from one of Feedbin's own apps. The app opens this page
# where it would open the authorize page, with the same parameters: the
# account is made, signed in, and the app authorized in one go, so the page
# ends back in the app as signing in does.
class Oauth::RegistrationsController < Oauth::BaseController
  before_action :set_application
  before_action :ensure_first_party

  def new
    @user = User.new
  end

  def create
    @user = User.sign_up_from_app(registration_params)
    if @user.persisted?
      Librato.increment("user.trial", source: "app")
      sign_in @user
      clear_location
      authorize_once(@application)
      redirect_to oauth_authorization_path(authorization_params)
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def registration_params
    params.permit(:email, :password)
  end

  def set_application
    @application = Doorkeeper::Application.by_uid(params[:client_id].to_s)
  end

  # Only Feedbin's own apps: anyone else's sends a newcomer to feedbin.com.
  def ensure_first_party
    render_404 unless @application && Api::V3::Scopes.first_party?(@application)
  end
end
