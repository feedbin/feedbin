class WorkerStat
  def call(worker, item, queue)
    title = "worker.#{worker.class.to_s.underscore}"
    Librato.increment "#{title}.count"
    Librato.increment "worker_perform"
    Librato.timing title do
      yield
    end
  end
end