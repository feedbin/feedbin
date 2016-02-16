present entry do |entry_presenter|
  if params.has_key?(:private)
    json.partial! "api/v2/entries/entry_private", entry: entry
  else
    json.extract! entry, :id, :feed_id, :title, :author, :summary
    json.content entry_presenter.api_content
    json.url entry.fully_qualified_url
    json.published entry.published.iso8601(6)
    json.created_at entry.created_at.iso8601(6)
    json.original entry.original if params[:include_original] == 'true'
    json.enclosure entry.data if params[:include_enclosure] == 'true'
    json.content_diff entry_presenter.content_diff if params[:include_content_diff] == 'true'
  end
end