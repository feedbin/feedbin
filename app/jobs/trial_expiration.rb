class TrialExpiration
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform
    expire_plan("trial")
    # expire_prepaid_users
  end

  def expire_prepaid_users
    user_ids = expire_plan("timed")
    user_ids.each do |user_id|
      UserMailer.delay.timed_plan_expiration(user_id)
    end
  end

  def expire_plan(stripe_id)
    plan = Plan.where(stripe_id: stripe_id)
    User.where(plan: plan, suspended: false).where("expires_at < ?", Time.now).pluck(:id).tap do |user_ids|
      if user_ids.present?
        Subscription.where(user_id: user_ids).update_all(active: false)
        User.where(id: user_ids).update_all(suspended: true)
      end
    end
  end

end
