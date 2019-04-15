class UserDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, signed_id = nil)
    @user = User.find(user_id)
    email_subscriptions
    refund_payment(signed_id)
    @user.destroy
  end

  def refund_payment(signed_id)
    begin
      id = Rails.application.message_verifier(:billing_event_id).verify(signed_id)
    rescue
      id = nil
    end

    if billing_event = @user.billing_events.find_by_id(id)
      Stripe::Refund.create(charge: billing_event.event_object["id"])
      Librato.increment("user.refund.accepted")
    else
      Librato.increment("user.refund.declined")
    end
  rescue Stripe::InvalidRequestError
  end

  def email_subscriptions
    tags = @user.feed_tags
    feeds = @user.feeds.xml
    titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) { |(feed_id, title), hash|
      hash[feed_id] = title
    }
    opml = SubscriptionsController.render(:index, assigns: {user: @user, tags: tags, feeds: feeds, titles: titles}, layout: nil)
    UserMailer.account_closed(@user.id, opml).deliver_now
  end
end
