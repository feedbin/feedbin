class AuthConstraint
  def self.admin?(request)
    auth_token = request.cookie_jar.signed[:auth_token]
    return false unless auth_token
    user = User.find_by_auth_token(auth_token)
    user&.admin?
  end
end
