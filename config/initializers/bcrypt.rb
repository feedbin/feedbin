BCrypt::Engine.cost = if ENV["BCRYPT_COST"]
  ENV["BCRYPT_COST"].to_i
elsif Rails.env.test?
  BCrypt::Engine::MIN_COST
else
  12
end
