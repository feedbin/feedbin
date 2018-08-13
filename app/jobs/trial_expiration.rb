class TrialExpiration
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform
    plan = Plan.where(stripe_id: "trial").first
    users = User.where(plan: plan, suspended: false).where("created_at < ?", Feedbin::Application.config.trial_days.days.ago)
    Subscription.where(user_id: users).update_all(active: false)
    users.update_all(suspended: true)
  end
end
