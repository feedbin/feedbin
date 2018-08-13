class SetPriceTier
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(user_id = nil, enqueue = false)
    enqueue ? _enqueue : _perform(user_id)
  end

  private

  def _perform(user_id)
    user = User.find(user_id)
    user.update(price_tier: user.plan.price_tier)
  end

  def _enqueue
    enqueue_all(User, self.class)
  end
end
