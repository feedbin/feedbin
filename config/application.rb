require_relative "boot"

require "rails/all"
require_relative "../lib/compressed_request"
require_relative "../lib/basic_authentication"
require_relative "../lib/conditional_sass_compressor"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Feedbin
  class Application < Rails::Application
    config.autoload_paths << "#{root}/app/views"
    config.autoload_paths << "#{root}/app/layouts"
    config.autoload_paths << "#{root}/app"

    config.eager_load_paths += %W(#{root}/app #{root}/app/views #{root}/app/views/components #{root}/app/views/layouts)

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Preserve SHA1 key derivation so existing session cookies and signed/encrypted
    # messages issued under the old default remain decryptable. Flipping to SHA256
    # would invalidate every active session.
    config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1

    # Preserve SHA1 hashing for cache keys and ETags. Flipping to SHA256 would
    # invalidate the entire cache on deploy.
    config.active_support.hash_digest_class = OpenSSL::Digest::SHA1

    # Keep YAML as the default coder for `serialize` columns without an explicit
    # coder. ImportItem#details is stored as YAML.
    config.active_record.default_column_serializer = ActiveRecord::Coders::YAMLColumn

    # Stay on MiniMagick — production does not have libvips installed for ActiveStorage.
    config.active_storage.variant_processor = :mini_magick

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    config.action_mailer.delivery_method   = :postmark
    config.action_mailer.postmark_settings = { api_token: ENV["POSTMARK_API_KEY"] }
    config.action_mailer.default_options   = { from: ENV["FROM_ADDRESS"] }

    config.action_view.sanitized_allowed_tags = "table", "tr", "td", "th", "thead", "tbody"

    config.middleware.use CompressedRequest

    config.middleware.use Rack::ContentLength

    config.middleware.use BasicAuthentication

    config.exceptions_app = routes

    config.active_record.schema_format = :sql

    config.action_dispatch.x_sendfile_header = "X-Accel-Redirect"

    config.sass.line_comments = true
    config.assets.compress = true
    config.action_view.automatically_disable_submit_tag = false
    config.active_record.belongs_to_required_by_default = false
    config.action_view.default_enforce_utf8 = true
    config.action_view.embed_authenticity_token_in_remote_forms = false
    config.active_record.yaml_column_permitted_classes = [Symbol]
    config.assets.css_compressor = ConditionalSassCompressor.new
    config.active_support.cache_format_version = 7.1
  end
end
