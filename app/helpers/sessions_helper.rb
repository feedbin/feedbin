module SessionsHelper

  def sign_in(user, remember_me = false)
    cookie_options = { value: user.auth_token, httponly: true, expires: 1.year.from_now, secure: Feedbin::Application.config.force_ssl }
    cookies.signed[:auth_token] = cookie_options
    self.current_user = user
  end

  def signed_in?
    !current_user.nil?
  end

  def current_user=(user)
    @current_user = user
  end

  def current_user
    if @current_user
      return @current_user
    end
    case params[:controller]
    when %r|^api/|
      if user = authenticate_with_http_basic { |username, password| User.where('lower(email) = ?', username.try(:downcase)).take.try(:authenticate, password) }
        @current_user = user
      else
        request_http_basic_authentication
      end
    else
      @current_user = User.find_by_auth_token(cookies.signed[:auth_token]) if cookies.signed[:auth_token]
    end
  end

  def authorize
    unless signed_in?
      flash[:error] = "Please log in."
      if request.xhr?
        render nothing: true, status: 401
      else
        store_location
        redirect_to login_url
      end
    end
  end

  def sign_out
    current_user = nil
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
