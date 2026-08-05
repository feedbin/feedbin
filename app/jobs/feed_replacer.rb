class FeedReplacer
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :default_critical

  def perform(user_id, subscription_id, discovered_feed_id = nil)
    user = User.find(user_id)

    # A retry after the existing-subscription branch below re-enters with a
    # subscription that has been destroyed. That run already did the work.
    return unless subscription = user.subscriptions.find_by(id: subscription_id)

    discovered_feed = if discovered_feed_id
      DiscoveredFeed.find(discovered_feed_id)
    else
      subscription.feed.discovered_feeds.order(created_at: :asc).take
    end

    if !discovered_feed
      subscription.fix_suggestion_ignored!
      return subscription
    end

    new_feed = FeedFinder.feeds(discovered_feed.feed_url)&.first
    old_feed = subscription.feed

    if new_feed == old_feed
      # A retry after a successful replacement reads the new feed as the
      # current one. The subscription is no longer flagged in that case, so
      # there is nothing to report and nothing to ignore.
      return subscription if subscription.fix_suggestion_none?

      ErrorService.notify(
        error_class: "FeedReplacer",
        error_message: "same feed",
        context: {
          user_id: user_id,
          subscription_id: subscription_id,
          discovered_feed_id: discovered_feed_id,
        }
      )

      subscription.fix_suggestion_ignored!
      return subscription
    end

    return unless new_feed && discovered_feed

    # One rewrite across four tables. A failure partway used to leave the
    # subscription on the new feed with the user's actions still naming the old
    # one, and the retry then took the same-feed path and abandoned the fix-up.
    ActiveRecord::Base.transaction do
      if existing = user.subscriptions.where(feed: new_feed).take
        subscription.destroy
        subscription = existing
      else
        subscription.update(feed: new_feed, fix_status: Subscription.fix_statuses[:none])
      end

      user.taggings.where(feed: old_feed).update(feed: new_feed)
      user.actions.where(all_feeds: true).each { _1.save }
      user.actions.where(":feed_id = ANY(feed_ids)", feed_id: old_feed.id.to_s).each do |action|
        new_feeds = action.feed_ids - [old_feed.id.to_s]
        new_feeds.push(new_feed.id.to_s)
        action.update(feed_ids: new_feeds)
      end
    end

    subscription
  end
end
