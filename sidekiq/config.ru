require 'sidekiq'
require 'sidekiq/web'

Sidekiq::Web.app_url = ENV['FEEDBIN_URL']

Sidekiq::Web.use Rack::Session::Cookie, secret: ENV["SECRET_KEY_BASE"]
Sidekiq::Web.instance_eval { @middleware.rotate!(-1) }

Sidekiq.configure_client do |config|
  config.redis = { :size => 1 }
end

map '/sidekiq' do
  use Rack::Auth::Basic, "Protected Area" do |username, password|
    web_password = ENV['SIDEKIQ_PASSWORD'] || 'secret'
    username == 'admin' && password == web_password
  end
  run Sidekiq::Web
end