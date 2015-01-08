class WorkerStat
  def call(worker, item, queue)
    Librato.timing "worker.#{worker.class.to_s.underscore}" do
      yield
    end
  end
end