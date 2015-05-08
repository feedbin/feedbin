if params.has_key?(:private)
  json.partial! "api/v2/entries/entry_private", entry: entry
else
  json.extract! entry, :id, :feed_id, :title, :author, :content, :summary
  json.url entry.fully_qualified_url
  json.published entry.published.iso8601(6)
  json.created_at entry.created_at.iso8601(6)
  json.original entry.original if params[:include_original] == 'true'
  json.enclosure entry.data if params[:include_enclosure] == 'true'
  if params[:include_content_diff] == 'true'
    begin
      before = ContentFormatter.api_format(entry.original['content'], entry)
      json.content_diff HTMLDiff::Diff.new(before, entry.content).inline_html
    rescue
      json.content_diff nil
    end
  end
end
