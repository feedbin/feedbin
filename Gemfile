source 'https://rubygems.org'

gem 'rails'

group :development do
  gem 'better_errors'
  gem 'quiet_assets'
  gem 'capistrano', github: 'capistrano/capistrano', ref: 'dcd3257'
  gem 'silencer'
  gem 'spring'
  gem 'benchmark-ips'
  gem 'xipio'
end

group :development, :test do
  gem 'rspec-rails', '~> 3.1'
  gem 'factory_girl_rails'
  gem 'faker'
end

group :test do
  gem "codeclimate-test-reporter", require: nil
end

group :production do
  gem "therubyracer", require: 'v8'
end

gem 'pg'
gem 'unicorn'

gem 'feedjira',              github: 'feedbin/feedjira',            ref: '43ba9b4'
gem 'opml_saw',              github: 'feedbin/opml_saw',            ref: '61d8c2d'
gem 'html-pipeline',         github: 'feedbin/html-pipeline',       ref: 'd7e451f'
gem 'grocer-pushpackager',   github: 'feedbin/grocer-pushpackager', ref: '6b01b4e', require: 'grocer/pushpackager'
gem 'html_diff',             github: 'feedbin/html_diff',           ref: 'c7c15ce'

gem 'sass-rails'
gem 'coffee-rails'
gem 'uglifier'
gem 'autoprefixer-rails'
gem 'rubyzip', '= 1.1.0'

gem 'activerecord-import', '>= 0.4.1'
gem 'redis', '= 3.2.2'
gem 'jquery-rails'
gem 'dalli'
gem 'will_paginate'
gem 'sanitize'
gem 'carrierwave'
gem 'carrierwave_direct'
gem 'fog'
gem 'clockwork'
gem 'bust_rails_etags'
gem 'jbuilder'
gem 'request_exception_handler'
gem 'bcrypt-ruby'
gem 'honeybadger'
gem 'addressable', require: 'addressable/uri'
gem 'librato-rails'
gem 'foreman', '= 0.63.0'
gem 'readability_parser'
gem 'lograge'
gem 'connection_pool'
gem 'httparty'
gem 'oauth'
gem 'evernote_oauth'
gem 'rmagick', require: false
gem 'reverse_markdown'
gem 'htmlentities'
gem 'rails-deprecated_sanitizer'
gem 'responders', '~> 2.0'
gem 'dotenv-rails'
gem 'kramdown'
gem 'rails_autolink'
gem 'premailer'
gem 'apnotic'
gem 'http'
gem 'elasticsearch-model'

# Sidekiq
gem 'sidekiq'
gem 'sinatra', require: nil

# Stripe
gem 'stripe', '= 1.9.9'
gem 'stripe_event'
