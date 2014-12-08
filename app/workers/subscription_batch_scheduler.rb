require_relative '../../lib/batch_jobs'

class SubscriptionBatchScheduler
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform
    total_records = Subscription.last.id
    jobs = job_args(total_records)
    Sidekiq::Client.push_bulk(
      'args'  => jobs,
      'class' => 'SubscriptionBatch',
      'queue' => 'worker_slow'
    )
  end

end