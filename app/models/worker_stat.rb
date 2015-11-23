class WorkerStat
  def call(worker, item, queue)
    title = "worker.#{worker.class.to_s.underscore}"
    Librato.increment "#{title}.count", source: Sidekiq::VERSION
    Librato.increment "worker_perform", source: Sidekiq::VERSION
    Librato.timing title, source: Sidekiq::VERSION do
      yield
    end
  end
end