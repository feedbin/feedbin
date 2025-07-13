class SavePageFromExtension
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: local_queue("parse_critical"), retry: false

  def perform(user_id, url, title, path)
    Sidekiq.logger.info "Saving page path=#{path}"
    SavePage.new.perform(user_id, url, title, path)
    # File.unlink(path) rescue Errno::ENOENT
  end
end
