source "https://rubygems.org"
git_source(:github) { |name| "https://github.com/#{name}.git" }

gem "rails", "7.1.3.4"
gem "will_paginate"

gem "http",                github: "feedbin/http",                branch: "feedbin"
gem "carrierwave",         github: "feedbin/carrierwave",         branch: "feedbin"
gem "sax-machine",         github: "feedbin/sax-machine",         branch: "feedbin"
gem "feedjira",            github: "feedbin/feedjira",            branch: "f2"
gem "feedkit",             github: "feedbin/feedkit",             branch: "master"
gem "html-pipeline",       github: "feedbin/html-pipeline",       branch: "feedbin"
gem "html_diff",           github: "feedbin/html_diff",           ref: "013e1bb"
gem "twitter",             github: "feedbin/twitter",             branch: "feedbin"

# https://github.com/mikel/mail/issues/1521
gem "mail", "< 2.8"

gem "activerecord-import"
gem "addressable", require: "addressable/uri"
gem "apnotic"
gem "autoprefixer-rails"
gem "bcrypt"
gem "bootsnap", require: false
gem "clockwork"
gem "coffee-rails"
gem "connection_pool"
gem "dotenv-rails", "= 2.8.1"
gem "down"
gem "evernote_oauth"
gem "fog-aws"
gem "honeybadger"
gem "htmlentities"
gem "httparty"
gem "image_processing"
gem "importmap-rails"
gem "jbuilder"
gem "jquery-rails"
gem "jwt"
gem "librato-rails", "~> 1.4.2"
gem "lograge"
gem "lookbook"
gem "net-http-persistent"
gem "oauth"
gem "oauth2"
gem "pg"
gem "phlex-rails"
gem "postmark-rails"
gem "premailer-rails"
# Unicorn is not yet compatible with rack 3
gem "rack", "< 3"
gem "raindrops"
gem "redcarpet"
gem "redis", "< 5"
gem "responders"
gem "reverse_markdown"
gem "ruby-vips"
gem "rubyzip", require: "zip"
gem "sanitize"
gem "sass-rails"
gem "sidekiq"
gem "stimulus-rails"
gem "stripe"
gem "stripe_event"
gem "strong_migrations"
gem "tailwindcss-rails"
gem "twitter-text"
gem "uglifier"
gem "unicorn"
gem "web-push"
gem "autotuner"

group :development do
  gem "benchmark-ips"
  gem "better_errors"
  gem "binding_of_caller"
  gem "htmlbeautifier"
  gem "listen"
  gem "foreman"
  gem "pry"
  gem "guard"
  gem "guard-minitest"
end

group :development, :test do
  gem "stripe-ruby-mock", github: "feedbin/stripe-ruby-mock", branch: "feedbin", require: "stripe_mock"
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "capybara", github: "teamcapybara/capybara"
  gem "debug"
  gem "faker"
  gem "minitest"
  gem "minitest-stub-const"
  gem "minitest-stub_any_instance"
  gem "puma"
  gem "rails-controller-testing"
  gem "selenium-webdriver"
  gem "standard"
  gem "webmock", "= 3.8.0"
  gem "phlex-testing-nokogiri"
end

