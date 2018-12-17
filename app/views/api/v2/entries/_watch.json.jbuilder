json.id entry.id
json.feed format_text(@titles[entry.feed_id] || entry.feed.title)
json.title format_text(entry.title)
json.author format_text(entry.author)
json.published entry.published.iso8601
json.content text_format(entry.content)
