json.feeds @feeds do |feed|
  json.id feed.id
  json.title feed.title
  json.feed_url feed.feed_url
  json.volume "#{feed.volume[feed.id].volume}/mo"
  json.last_article timeago_text(feed.last_published_entry)
end

json.tags @user.tag_group.map(&:name)