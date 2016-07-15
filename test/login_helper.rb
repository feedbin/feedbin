require "bcrypt"

module LoginHelper

  def login_as(user)
    cookies.signed[:auth_token] = user.auth_token
  end

  def default_password_digest
    BCrypt::Password.create(default_password, cost: 4)
  end

  def default_password
    "password"
  end
end
