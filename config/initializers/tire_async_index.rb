TireAsyncIndex.configure do |config|
  config.background_engine :sidekiq
  config.use_queue :default
end