present entry do |entry_presenter|
  json.extract! entry, :id, :feed_id, :title, :author, :summary
  json.content entry_presenter.api_content
  json.url entry.fully_qualified_url
  json.published entry.published.iso8601(6)
  json.created_at entry.created_at.iso8601(6)
  json.original entry.original
  json.content_diff entry_presenter.content_diff if params[:include_content_diff] == "true"
  json.twitter_id entry.twitter_id
  json.twitter_thread_ids entry.twitter_thread_ids
  json.extracted_content_url entry.extracted_content_url
  json.images do
    if entry.processed_image?
      json.original_url entry.image["original_url"]
      json.size_1 do
        json.cdn_url entry.processed_image
        json.width entry.image["width"]
        json.height entry.image["height"]
      end
    else
      json.null!
    end
  end
  json.enclosure do
    if entry_presenter.has_enclosure?
      json.enclosure_url entry_presenter.enclosure_url
      json.enclosure_type entry.data["enclosure_type"]
      json.enclosure_length entry.data["enclosure_length"]
      json.itunes_duration entry.data["itunes_duration"]
      json.itunes_image entry.data["itunes_image"]
    else
      json.null!
    end
  end
  json.extracted_articles entry_presenter.extracted_articles do |article|
    json.merge! article
  end
  json.extract! entry, :json_feed
end
