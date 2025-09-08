class FeedReplacer
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :default_critical

  def perform(user_id, subscription_id, discovered_feed_id = nil)
    user = User.find(user_id)

    subscription = user.subscriptions.find(subscription_id)

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

    subscription
  end
end
