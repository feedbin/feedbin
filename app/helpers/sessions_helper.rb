module SessionsHelper
  def sign_in(user, remember_me = false)
    update_auth_cookie(user)
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

  def redirect_back_or(default, notice = nil)
    redirect_to (clear_location || default), notice: notice
  end

  def store_location
    session[:return_to] = request.url
  end

  def clear_location
    session.delete(:return_to)
  end
end
