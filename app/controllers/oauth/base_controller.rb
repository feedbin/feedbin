# The base of Doorkeeper's authorization controller. Signed-out visitors are
# let through: the authorize page signs them in itself.
class Oauth::BaseController < ApplicationController
  OAUTH_PARAMS = %i[client_id redirect_uri state response_type response_mode scope code_challenge code_challenge_method]

  layout false

  skip_before_action :authorize
  before_action :assign_v3_scopes

  private

  # Doorkeeper's resource_owner_authenticator. Nil renders the page signed out.
  def oauth_resource_owner
    if signed_in?
      require_api_v3
      current_user unless performed?
    elsif request.post?
      sign_in_resource_owner
    else
      # Signing up or resetting a password elsewhere comes back here, unless
      # the visitor cancelled.
      request.get? ? store_location : clear_location
      nil
    end
  end

  def sign_in_resource_owner
    user = User.find_by_email(params[:email])
    if !user&.authenticate(params[:password])
      refuse_sign_in "Invalid email or password"
    elsif !user.api_v3_enabled?
      refuse_sign_in "This account can’t connect apps yet."
    else
      sign_in user
      clear_location
      user
    end
  end

  def refuse_sign_in(message)
    flash[:error] = message
    # The flash rides in the session cookie, which a long enough value overflows.
    flash[:email] = params[:email].to_s.first(255)
    redirect_to oauth_authorization_path(authorization_params)
    nil
  end

  def authorization_params
    params.permit(*OAUTH_PARAMS).to_h
  end

  # An account made on the app's own sign-up page (Oauth::RegistrationsController)
  # is for that app: the next visit to the authorize page, which is the one
  # that page redirects to, answers the app without asking. Once.
  def authorize_once(application)
    session[:oauth_authorize_once] = application.uid
  end

  # Doorkeeper's skip_authorization.
  def authorizing_once?(client)
    session.delete(:oauth_authorize_once) == client.uid
  end

  # Requested scopes are replaced by Api::V3::Scopes.
  def assign_v3_scopes
    application = Doorkeeper::Application.by_uid(params[:client_id].to_s)
    params[:scope] = Api::V3::Scopes.for(application) if application
  end
end
