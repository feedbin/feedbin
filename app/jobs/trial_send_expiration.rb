class TrialSendExpiration
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(user_id)
    user = User.find(user_id)
    if user.plan.stripe_id == "trial" && user.subscriptions.exists?
      UserMailer.trial_expiration(user_id).deliver
    end
  rescue ActiveRecord::RecordNotFound
  end
end
