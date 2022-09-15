class LogEnv
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "ENV #{ENV.inspect}"
  end
end
