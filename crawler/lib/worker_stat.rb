class WorkerStat
  def call(worker, item, queue)
    title = "worker.#{worker.class}"
    Librato.increment "#{title}.count", source: Socket.gethostname
    Librato.timing title, source: Socket.gethostname do
      yield
    end
  end
end
