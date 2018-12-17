require "bcrypt"

module LoginHelper
  def login_as(user)
    if @request.subdomain == "api"
      @request.headers[:authorization] = ActionController::HttpAuthentication::Basic.encode_credentials(user.email, default_password)
    else
      cookies.signed[:auth_token] = user.auth_token
    end
  end

  def default_password_digest
    BCrypt::Password.create(default_password, cost: 4)
  end

  def default_password
    "password"
  end
end
