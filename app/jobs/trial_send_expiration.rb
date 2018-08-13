class TrialSendExpiration
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.where(id: user_id).first
    if user.present? && user.plan.stripe_id == "trial"
      UserMailer.trial_expiration(user_id).deliver
    end
  end
end
