published = entry.published || Time.parse(entry.original['published'])
json.extract! entry, :id, :feed_id, :title, :author, :content
json.summary nil
json.url entry.fully_qualified_url
json.published published.iso8601(6)
json.created_at entry.created_at.iso8601(6)