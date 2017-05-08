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
    if params[:include_enclosure] == 'true' && entry_presenter.has_enclosure?
        json.enclosure do
            json.enclosure_url entry.data["enclosure_url"]
            json.enclosure_type entry.data["enclosure_type"]
            json.enclosure_length entry.data["enclosure_length"]
            json.itunes_duration entry.data["itunes_duration"]
        end
    end
    json.content_diff entry_presenter.content_diff if params[:include_content_diff] == 'true'
  end
end
