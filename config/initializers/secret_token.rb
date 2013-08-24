# Be sure to restart your server when you modify this file.

# Your secret key for verifying the integrity of signed cookies.
# If you change this key, all old signed cookies will become invalid!

# Make sure the secret is at least 30 characters and all random,
# no regular words or you'll be exposed to dictionary attacks.
# You can use `rake secret` to generate a secure secret key.

# Make sure your secret_key_base is kept private
# if you're sharing your code publicly.

# Make sure warning shows up if trying to use default secret_key_base in production
if Rails.env.production?
  secret_key_base = ENV['SECRET_KEY_BASE']
else
  secret_key_base = 'd93da6cdec959ae3fa7e3417070d58'
end

Feedbin::Application.config.secret_key_base = secret_key_base
