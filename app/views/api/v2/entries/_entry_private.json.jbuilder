decoder = HTMLEntities.new
content_text = Sanitize.fragment(entry.content,
  elements: %w{h1 h2 h3 h4 h5 h6 p blockquote pre a abbr acronym address big cite code del dfn em ins kbd q s samp small strike strong sub sup tt var b u i center dl dt dd ol ul li},
  remove_contents: true
)
content_text = ReverseMarkdown.convert(content_text)
json.extract! entry, :id, :feed_id
json.title entry.title
json.author decoder.decode(strip_tags(entry.author))
json.content ContentFormatter.app_format(entry.content, entry)
json.content_text decoder.decode(content_text)
json.summary decoder.decode(strip_tags(entry.summary))
json.url entry.fully_qualified_url
json.published entry.published.iso8601(6)
json.created_at entry.created_at.iso8601(6)
