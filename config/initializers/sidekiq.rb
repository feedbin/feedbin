require 'sidekiq'
require 'sidekiq/web'

Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  web_password = ENV['SIDEKIQ_PASSWORD'] || 'secret'
  username == 'admin' && password == web_password
end

Sidekiq.configure_server do |config|
  ActiveRecord::Base.establish_connection
end
