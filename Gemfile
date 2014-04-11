source 'https://rubygems.org'
ruby '2.1.1'

gem 'rails', '~>4.0.0'

group :development do
  gem 'better_errors'
  gem 'quiet_assets'
  gem 'capistrano', '~> 2.15.5'
  gem 'capistrano-unicorn', github: 'sosedoff/capistrano-unicorn', ref: '52376ad', require: false
  gem 'dotenv-rails'
end

group :production do
  gem "therubyracer", require: 'v8'
end

gem 'pg'
gem 'unicorn'

gem 'opml_saw',              github: 'feedbin/opml_saw',            ref: '61d8c2d'
gem 'feedzirra',             github: 'feedbin/feedzirra',           ref: 'c7a1f10'
gem 'html-pipeline',         github: 'benubois/html-pipeline',      ref: '0d85834'
gem 'grocer-pushpackager',   github: 'feedbin/grocer-pushpackager', ref: 'e190796', require: 'grocer/pushpackager'
gem 'html_diff',             github: 'feedbin/html_diff',           ref: 'c7c15ce'

gem 'sass-rails', '~>4.0.0'
gem 'coffee-rails', '~>4.0.0'
gem 'uglifier', '>= 1.0.3'
gem 'autoprefixer-rails'
gem 'rubyzip', '= 1.1.0'

gem 'activerecord-import', '>= 0.4.1'
gem 'redis', '>= 3.0.5'
gem 'jquery-rails'
gem 'dalli'
gem 'will_paginate'
gem 'sanitize'
gem 'longurl'
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
gem 'librato-rails', '= 0.9.0'
gem 'foreman'
gem 'yajl-ruby', require: nil
gem 'readability_parser'
gem 'lograge'
gem 'tire'
gem 'grocer'
gem 'cocoon'
gem 'gctools', require: false
gem 'connection_pool'
gem 'httparty'
gem 'oauth'

# Sidekiq
gem 'sidekiq'
gem 'sinatra', require: nil

# Stripe
gem 'stripe', '= 1.9.9'
gem 'stripe_event'
