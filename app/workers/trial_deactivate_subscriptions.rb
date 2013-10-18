class TrialDeactivateSubscriptions
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(user_id)
    user = User.where(id: user_id).first
    if user.present? && user.plan.stripe_id == 'trial'
      user.subscriptions.update_all(active: false)
    end
  end

end
