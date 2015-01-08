require File.expand_path('../boot', __FILE__)

require 'rails/all'
require_relative '../lib/basic_authentication'

# Assets should be precompiled for production (so we don't need the gems loaded then)
Bundler.require(*Rails.groups(assets: %w(development test)))

module Feedbin
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Version of your assets, change this if you want to expire all your assets
    config.assets.version = '1.0'
    config.assets.initialize_on_precompile = true
    config.serve_static_assets = true

    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address:              ENV['SMTP_ADDRESS'],
      port:                 587,
      enable_starttls_auto: true,
      authentication:       'login',
      user_name:            ENV['SMTP_USERNAME'],
      password:             ENV['SMTP_PASSWORD'],
      domain:               ENV['DEFAULT_URL_OPTIONS_HOST']
    }

    config.action_view.sanitized_allowed_tags = 'table', 'tr', 'td', 'th', 'thead', 'tbody'

    config.middleware.use Rack::ContentLength

    config.middleware.use BasicAuthentication

    config.exceptions_app = self.routes

    config.active_record.schema_format = :sql

  end
end