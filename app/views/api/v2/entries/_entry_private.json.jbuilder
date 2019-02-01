present entry do |entry_presenter|
  json.extract! entry, :id, :feed_id
  json.title entry_presenter.app_title
  json.author entry_presenter.app_author
  json.content entry_presenter.app_content
  json.content_text entry_presenter.content_text
  json.summary entry_presenter.app_summary
  json.url entry.fully_qualified_url
  json.published entry.published.iso8601(6)
  json.created_at entry.created_at.iso8601(6)
end
