class BatchScheduler
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(klass, worker_class)
    klass = klass.constantize
    total_records = klass.last.id
    jobs = job_args(total_records)
    Sidekiq::Client.push_bulk(
      "args" => jobs,
      "class" => worker_class,
      "queue" => "worker_slow",
    )
  end
end
