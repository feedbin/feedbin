require_relative '../../lib/batch_jobs'

class SubscriptionBatch

  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(batch)
    ids = build_ids(batch)
    Subscription.where(id: ids).update_all(show_updates: true)
  end

end