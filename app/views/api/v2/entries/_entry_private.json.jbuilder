decoder = HTMLEntities.new
content_text = Sanitize.fragment(entry.content,
  remove_contents: true,
  elements: %w{html body div span
               h1 h2 h3 h4 h5 h6 p blockquote pre
               a abbr acronym address big cite code
               del dfn em ins kbd q s samp
               small strike strong sub sup tt var
               b u i center
               dl dt dd ol ul li
               fieldset form label legend
               table caption tbody tfoot thead tr th td
               article aside canvas details embed
               figure figcaption footer header hgroup
               menu nav output ruby section summary}
)

title = (entry.title.present?) ? decoder.decode(strip_tags(entry.title.strip)) : nil
author = (entry.author.present?) ? decoder.decode(strip_tags(entry.author.strip)) : nil
content_text = ReverseMarkdown.convert(content_text)
content_text = ActionController::Base.helpers.strip_tags(content_text)

json.extract! entry, :id, :feed_id
json.title title
json.author author
json.content ContentFormatter.app_format(entry.content, entry)
json.content_text decoder.decode(content_text)
json.summary decoder.decode(strip_tags(entry.summary))
json.url entry.fully_qualified_url
json.published entry.published.iso8601(6)
json.created_at entry.created_at.iso8601(6)
