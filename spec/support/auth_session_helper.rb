module AuthSessionHelper
  def sign_in(user)
    if user.auth_token.blank?
      raise ArgumentError.new("empty auth_token")
    end

    cookies.signed[:auth_token] = user.auth_token
  end
end
