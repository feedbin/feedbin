class ApplicationMailer < ActionMailer::Base
  # Mail goes out with deliver_later on Sidekiq's default 25 attempts over
  # roughly three weeks. Postmark tells us which failures are permanent — a
  # hard-bounced or deactivated address — and those fail identically every
  # time, so retrying them only produces alert volume. Anything Postmark says
  # is worth retrying keeps the default policy.
  rescue_from Postmark::ApiInputError do |exception|
    raise exception if exception.retry?
    Rails.logger.warn "Discarding mail Postmark will not accept: #{exception.message}"
  end
end
