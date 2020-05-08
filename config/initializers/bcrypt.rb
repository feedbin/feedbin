BCrypt::Engine.cost = ENV["BCRYPT_COST"] ? ENV["BCRYPT_COST"].to_i : 12
