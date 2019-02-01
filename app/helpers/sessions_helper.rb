module SessionsHelper
  def sign_in(user, remember_me = false)
    cookie_options = {value: user.auth_token, httponly: true, expires: 1.year.from_now, secure: Feedbin::Application.config.force_ssl}
    cookies.signed[:auth_token] = cookie_options
    @current_user = user
  end

  def signed_in?
    current_user.present?
  end

  def current_user
    @current_user ||= begin
      if request.subdomain == "api"
        authenticate_with_http_basic do |username, password|
          User.where("lower(email) = ?", username.try(:downcase)).take.try(:authenticate, password)
        end
      else
        User.find_by_auth_token(cookies.signed[:auth_token].to_s) if cookies.signed[:auth_token].respond_to?(:to_s)
      end
    end
  end

  def authorize
    unless signed_in?
      if request.subdomain == "api"
        request_http_basic_authentication
      else
        flash[:notice] = "Please log in."
        if request.xhr?
          head :unauthorized
        else
          store_location
          redirect_to login_url
        end
      end
    end
  end

  def sign_out
    @current_user = nil
    cookies.delete(:auth_token)
  end

  def redirect_back_or(default)
    redirect_to(session[:return_to] || default)
    session.delete(:return_to)
  end

  def store_location
    session[:return_to] = request.url
  end
end
