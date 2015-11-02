require 'rack'

class AuthConstraint
  def self.admin?(request)
    if auth_token = request.cookies["auth_token"]
      auth_token = Rack::Session::Cookie::Base64::Marshal.new.decode(auth_token)
      user = User.find_by_auth_token(auth_token)
      user && user.admin?
    else
      false
    end
  end
end