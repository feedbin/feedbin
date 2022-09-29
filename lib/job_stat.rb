class JobStat
  def call(worker, item, queue)
    title = "job.#{worker.class.to_s.underscore.parameterize}"
    Librato.increment "#{title}.count", source: Socket.gethostname
    Librato.increment "worker_perform", source: Socket.gethostname
    Librato.timing title, source: Socket.gethostname do
      yield
    end
  end
end
