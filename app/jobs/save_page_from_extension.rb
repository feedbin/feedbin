class SavePageFromExtension
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: local_queue("parse_critical"), retry: false

  def perform(user_id, url, title, path)
    Sidekiq.logger.info "Saving page path=#{path}"
    SavePage.new.perform(user_id, url, title, path)
  # This worker never retries, so the raise that schedules SavePage's own
  # re-crawl could only land in the error tracker. Hand the retry to the
  # worker that has one — a url crawl needs no captured file. Same shape as
  # PagesInternalController's rescue.
  rescue SavePage::MissingPage
    Sidekiq.logger.info "Captured page could not be parsed, retrying by url url=#{url}"
    SavePage.perform_async(user_id, url, title)
  # In an ensure because this worker does not retry -- the run that fails is
  # the only one that will ever be in a position to remove the file.
  ensure
    File.unlink(path) if path && File.exist?(path)
  end
end
