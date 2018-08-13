ActiveSupport::Reloader.to_prepare do
  ApplicationController.renderer.defaults.merge!(
    http_host: ENV["DEFAULT_URL_OPTIONS_HOST"],
    https: Feedbin::Application.config.force_ssl,
  )
end
