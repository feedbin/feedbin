class JobStat
  def call(job, item, queue)
    title = "job.#{job.class.to_s.underscore.parameterize}"
    Honeybadger.increment_counter "#{title}.count"
    Honeybadger.increment_counter "job.count"
    Honeybadger.time title, -> { yield }, source: Socket.gethostname
  end
end
