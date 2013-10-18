class TrialEnd
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.where(id: user_id).first
    if user.present? && user.plan.stripe_id == 'trial'
      user.suspended = true
      user.save
    end
  end

end
