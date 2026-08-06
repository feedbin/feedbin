class SavePageFromExtension
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: local_queue("parse_critical"), retry: false

  def perform(user_id, url, title, path)
    Sidekiq.logger.info "Saving page path=#{path}"
    SavePage.new.perform(user_id, url, title, path)
  # In an ensure because SavePage raises MissingPage for a page the extract
  # service cannot read, and this worker does not retry -- so the run that
  # fails is the only one that will ever be in a position to remove the file.
  ensure
    File.unlink(path) if path && File.exist?(path)
  end
end
