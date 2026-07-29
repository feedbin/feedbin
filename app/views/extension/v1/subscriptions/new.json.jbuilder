def subscription_for(feed)
  @subscriptions[feed.id] || @subscriptions[feed.feed_url]
end

json.feeds @feeds do |feed|
  subscription = subscription_for(feed)

  json.id feed.id
  json.title feed.title
  json.feed_url feed.feed_url
  json.volume "#{feed.volume[feed.id].volume}/mo"
  json.subscribed subscription.present?

  json.manage_url subscription && edit_settings_subscription_url(subscription)
  json.muted subscription&.muted? || false
  json.crawl_error subscription&.feed&.crawl_error? || false
  json.tags subscription ? @tag_names.fetch(subscription.feed_id, []) : []
end

json.tags @user.tag_group.map(&:name)
