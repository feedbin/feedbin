require_relative "boot"

require "rails/all"
require_relative "../lib/basic_authentication"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Feedbin
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: 587,
      enable_starttls_auto: true,
      authentication: "login",
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      domain: ENV["SMTP_DOMAIN"] || ENV["DEFAULT_URL_OPTIONS_HOST"],
    }

    config.action_view.sanitized_allowed_tags = "table", "tr", "td", "th", "thead", "tbody"

    config.middleware.use Rack::ContentLength

    config.middleware.use BasicAuthentication

    config.exceptions_app = self.routes

    config.active_record.schema_format = :sql
  end
end
