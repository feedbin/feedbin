class WebSubMaintenance
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform
    subscribe.each do |feed|
      WebSubSubscribe.perform_in(sometime_today, feed.id)
    end

    unsubscribe.each do |feed|
      WebSubUnsubscribe.perform_in(sometime_today, feed.id)
    end
  end

  def sometime_today
    rand(0..1.day.to_i).seconds
  end

  def subscribe
    Feed.where("push_expiration < ?", Time.now)
      .or(Feed.where(push_expiration: nil))
      .where("last_published_entry > ?", 1.month.ago)
      .where("cardinality(hubs) > 0")
      .joins(:subscriptions)
      .select("feeds.id, COUNT(subscriptions.*) AS subscriptions_count")
      .where(subscriptions: { active: true })
      .group("feeds.id")
  end

  def unsubscribe
    Feed.where(subscriptions_count: 0).where("cardinality(hubs) > 0").where.not(push_expiration: nil)
  end
end
