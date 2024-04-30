Rails.application.configure do
  config.active_job.queue_adapter = :sidekiq
  config.action_mailer.deliver_later_queue_name = "default_critical"
end
