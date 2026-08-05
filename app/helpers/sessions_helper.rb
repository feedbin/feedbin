module SessionsHelper
  def sign_in(user, remember_me = false)
    update_auth_cookie(user)
    @current_user = user
  end

  def signed_in?
    current_user.present?
  end

  # `defined?` rather than `||=`: a signed-out request resolves to nil, which
  # `||=` does not cache, so the lookup ran again on every call.
  def current_user
    return @current_user if defined?(@current_user)
    @current_user = find_current_user
  end

  def find_current_user
    if request.subdomain == "api"
      http_basic_user
    else
      User.find_by_auth_token(cookies.signed[:auth_token].to_s) if cookies.signed[:auth_token].respond_to?(:to_s)
    end
  end

  # This module is mixed into every view as well as the controller, and
  # authenticate_with_http_basic is a controller method -- so any view that
  # asked for current_user on the api subdomain raised NoMethodError, which is
  # every unauthenticated HTML request there. HttpAuthentication::Basic's own
  # module functions read the same header and work from either side.
  def http_basic_user
    return nil unless ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)
    username, password = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
    user = User.find_by_email(username)
    user if user&.authenticate(password)
  end

  def authorize
    unless signed_in?
      if request.subdomain == "api"
        request_http_basic_authentication
      else
        flash[:notice] = "Please sign in."
        if request.xhr?
          head :unauthorized
        else
          store_location
          redirect_to login_url
        end
      end
    end
  end

  def update_auth_cookie(user)
    return unless user
    cookie_options = {value: user.auth_token, httponly: true, expires: 1.year.from_now, secure: Feedbin::Application.config.force_ssl}
    cookies.signed[:auth_token] = cookie_options
  end

  def sign_out
    @current_user = nil
    reset_session
    cookies.delete(:auth_token)
  end

  def redirect_back_or(default, options = {})
    redirect_to clear_location || default, **options
  end

  def store_location
    session[:return_to] = request.url
  end

  def clear_location
    session.delete(:return_to)
  end
end
