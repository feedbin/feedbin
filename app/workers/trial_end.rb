class TrialEnd
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    # noop. Moved logic to trial_expiration
  end

end
