require 'rack_headers'

Feedbin::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both thread web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like nginx, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Compress JavaScripts and CSS
  config.assets.compress = true

  config.assets.js_compressor = :uglifier

  # Whether to fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Generate digests for assets URLs.
  config.assets.digest = true

  # Version of your assets, change this if you want to expire all your assets.
  config.assets.version = '1.0'

  # Rack Headers
  # Set HTTP Headers on static assets
  config.assets.header_rules = [
    # Cache all static files in public caches (e.g. Rack::Cache)
    #  as well as in the browser
    [:all,   {'Cache-Control' => 'public, max-age=31536000'}],

    # Provide web fonts with cross-origin access-control-headers
    #  Firefox requires this when serving assets using a Content Delivery Network
    [:fonts, {'Access-Control-Allow-Origin' => '*'}]
  ]
  config.middleware.insert_before '::ActionDispatch::Static', '::Rack::Headers'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for apache
  config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for nginx

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Less verbose logs
  config.lograge.enabled = true

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Set to :debug to see everything in the log.
  config.log_level = :info
  config.logger = Logger.new(STDOUT)

  # Recommended by http://help.papertrailapp.com/kb/configuration/unicorn
  config.logger.level = Logger.const_get('INFO')

  # Prepend all log lines with the following tags.
  config.log_tags = [ :subdomain, :uuid ]

  # Disable automatic flushing of the log to improve performance.
  # config.autoflush_log = false

  config.cache_store = :dalli_store, ENV['MEMCACHED_HOSTS'].split(',')

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  config.action_controller.asset_host = ENV['ASSET_HOST']

  # Precompile additional assets.
  # application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
  # config.assets.precompile += %w( search.js )

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  config.action_mailer.default_url_options = { host: ENV['DEFAULT_URL_OPTIONS_HOST'], protocol: 'https' }

end
