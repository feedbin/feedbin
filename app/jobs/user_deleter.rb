class UserDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(user_id, signed_id = nil)
    @user = User.find(user_id)
    # Render the export while the associations still exist, but deliver it
    # after the account is gone: the user has already been signed out and told
    # the account is closed, so a mail failure must not leave the record — and
    # the Stripe subscription cancelled in before_destroy — alive.
    email = @user.email
    opml = subscriptions_opml
    refund_payment(signed_id)
    @user.destroy
    email_subscriptions(email, opml)
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

  def subscriptions_opml
    tags = @user.feed_tags
    feeds = @user.feeds.xml
    titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) { |(feed_id, title), hash|
      hash[feed_id] = title
    }
    SubscriptionsController.render(:index, assigns: {user: @user, tags: tags, feeds: feeds, titles: titles}, layout: nil)
  end

  # InactiveRecipientError is one of several siblings under ApiInputError, all
  # of which mean the address is permanently undeliverable.
  def email_subscriptions(email, opml)
    UserMailer.account_closed(email, opml).deliver_now
  rescue Net::SMTPSyntaxError, Postmark::ApiInputError
  end
end
