title = titles[feed.id] || feed.title
xml.outline text: title, title: title, type: "rss", xmlUrl: feed.feed_url, htmlUrl: feed.site_url
