source "https://rubygems.org"
git_source(:github) { |name| "https://github.com/#{name}.git" }

gem "rails", github: "rails/rails", branch: "6-0-stable"

gem "rails-controller-testing"
gem "rails_autolink"
gem "responders"
gem "rack", github: "rack/rack", ref: "4ebd70b"

group :development do
  gem "capistrano"
  gem "capistrano-bundler"
  gem "capistrano-rails"
  gem "better_errors"
  gem "binding_of_caller"
  gem "silencer"
  gem "benchmark-ips"
  gem "listen"
  gem "htmlbeautifier"
  gem "spring"
end

group :development, :test do
  gem "puma"
  gem "minitest"
  gem "stripe-ruby-mock", "= 2.5.0", require: "stripe_mock"
  gem "faker"
  gem "webmock", "= 3.8.0"
  gem "minitest-stub-const"
  gem "coveralls", require: false
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "capybara"
  gem "selenium-webdriver"
  gem "minitest-stub_any_instance"
  gem "standard"
end

gem "pg"
gem "unicorn"

gem "feedjira", github: "feedbin/feedjira", ref: "e6b7b11"
gem "feedkit", github: "feedbin/feedkit", branch: "master"

gem "opml_saw", github: "feedbin/opml_saw", ref: "61d8c2d"
gem "html-pipeline", github: "feedbin/html-pipeline", ref: "20162f9"
gem "grocer-pushpackager", github: "feedbin/grocer-pushpackager", ref: "6b01b4e", require: "grocer/pushpackager"
gem "html_diff", github: "feedbin/html_diff", ref: "c7c15ce"
gem "carrierwave_direct", github: "feedbin/carrierwave_direct", ref: "a0bc323"
gem "dalli", github: "feedbin/dalli", branch: "feedbin"


gem "sass-rails"
gem "mini_racer"
gem "coffee-rails"
gem "uglifier", "= 4.1.11"
gem "autoprefixer-rails"
gem "rubyzip"

gem "apnotic"
gem "json"
gem "activerecord-import", ">= 0.4.1"
gem "redis"
gem "jquery-rails"
gem "will_paginate"
gem "sanitize"
gem "carrierwave"
gem "fog-aws"
gem "clockwork"
gem "jbuilder"
gem "bcrypt-ruby"
gem "honeybadger"
gem "addressable", require: "addressable/uri"
gem "librato-rails", "= 1.4.2"
gem "foreman", "= 0.63.0"
gem "readability_parser"
gem "lograge"
gem "connection_pool"
gem "httparty"
gem "oauth"
gem "evernote_oauth"
gem "rmagick", require: false
gem "reverse_markdown"
gem "htmlentities"
gem "dotenv-rails"
gem "kramdown"
gem "premailer-rails"
gem "http"
gem "net-http-persistent"
gem "elasticsearch", "~> 2.0"
gem "elasticsearch-model", "~> 2.0"
gem "sidekiq"
gem "raindrops"
gem "curb"
gem "twitter"
gem "twitter-text"
gem "bootsnap", require: false
gem "unicode-emoji"
gem "rack-attack"
gem "jbuilder_cache_multi"
gem "bcrypt"

# Stripe
gem "stripe", "~> 5.17.0"
gem "stripe_event"
