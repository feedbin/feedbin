json.feeds @feeds do |feed|
  json.id feed.id
  json.title feed.title
  json.feed_url feed.feed_url
  json.volume "#{feed.volume[feed.id].volume}/mo"
end

json.tags @user.tag_group.map(&:name)