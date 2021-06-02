require_relative "boot"

require "rails/all"
require_relative "../lib/basic_authentication"
require_relative "../lib/tld_length"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Feedbin
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    config.action_mailer.delivery_method   = :postmark
    config.action_mailer.postmark_settings = { api_token: ENV["POSTMARK_API_KEY"] }
    config.action_mailer.default_options   = { from: ENV["FROM_ADDRESS"] }

    config.action_view.sanitized_allowed_tags = "table", "tr", "td", "th", "thead", "tbody"

    config.middleware.use Rack::ContentLength

    config.middleware.use Rack::Attack

    config.middleware.use BasicAuthentication

    config.middleware.use TldLength

    config.exceptions_app = routes

    config.active_record.schema_format = :sql

    config.sass.line_comments = true
    config.assets.compress = true
    config.action_view.automatically_disable_submit_tag = false
    config.active_record.belongs_to_required_by_default = false
    config.action_view.default_enforce_utf8 = true
  end
end
