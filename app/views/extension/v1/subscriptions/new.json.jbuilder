def already_subscribed?(feed)
  @subscriptions.include?(feed.id) || @subscriptions.include?(feed.feed_url)
end

json.feeds @feeds do |feed|
  json.id feed.id
  json.title feed.title
  json.feed_url feed.feed_url
  json.volume "#{feed.volume[feed.id].volume}/mo"
  json.subscribed already_subscribed?(feed)
end

json.tags @user.tag_group.map(&:name)