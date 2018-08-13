class FaviconMigration
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(favicon_id = nil, schedule = false)
    if schedule
      build
    else
      upload(favicon_id)
    end
  rescue ActiveRecord::RecordNotFound
  end

  def upload(favicon_id)
    favicon = Favicon.unscoped.find(favicon_id)
    if favicon.favicon
      data = Base64.decode64(favicon.favicon)
      processor = FaviconProcessor.new(data, favicon.host)
      favicon.url = processor.upload_existing
      favicon.save
    end
  end

  def build
    enqueue_all(Favicon, self.class)
  end
end
