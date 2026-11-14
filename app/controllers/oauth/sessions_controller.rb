# "Not you?" on the authorize page: signs out and returns to it.
class Oauth::SessionsController < Oauth::BaseController
  def destroy
    sign_out
    redirect_to oauth_authorization_path(authorization_params)
  end
end
