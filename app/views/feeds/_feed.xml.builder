if titles[feed.id]
  title = titles[feed.id]
else
  title = feed.title
end
xml.outline text: title, title: title, type: 'rss', xmlUrl: feed.feed_url, htmlUrl: feed.site_url