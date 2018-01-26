class UserDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, billing_event_id = nil)
    @user = User.find(user_id)
    email_subscriptions(user)
    refund_payment(user, billing_event_id)
    @user.destroy
  end

  def refund_payment(user, billing_event_id)
    begin
      id = Rails.application.message_verifier(:billing_event_id).verify(billing_event_id)
    rescue
      id = nil
    end

    if billing_event = user.billing_events.find_by_id(payment_id)
      Stripe::Refund.create(charge: billing_event.event_object["id"])
    end
  end

  def email_subscriptions(user)
    tags = user.feed_tags
    feeds = user.feeds.xml
    titles = user.subscriptions.pluck(:feed_id, :title).each_with_object({}) do |(feed_id, title), hash|
      hash[feed_id] = title
    end
    opml = SubscriptionsController.render(:index, assigns: {user: user, tags: tags, feeds: feeds, titles: titles}, layout: nil)
    UserMailer.account_closed(user.id, opml).deliver_now
  end

end