json.id            @feed.id
json.title         @feed.try(:title).clean(transform: [:to_plain_text])
json.home_page_url @feed.try(:site_url).clean
json.feed_url      @feed.try(:feed_url).clean
json.description   @feed.options&.safe_dig("description").clean(transform: [:to_plain_text])

json.podcast do
  json.author       @feed.options&.safe_dig("itunes_author").clean
  json.block        @feed.options&.safe_dig("itunes_block").clean
  json.complete     @feed.options&.safe_dig("itunes_complete").clean
  json.explicit     @feed.options&.safe_dig("itunes_explicit").clean
  json.image        @feed.options&.safe_dig("itunes_image").clean
  json.keywords     @feed.options&.safe_dig("itunes_keywords").clean
  json.new_feed_url @feed.options&.safe_dig("itunes_new_feed_url").clean
  json.subtitle     @feed.options&.safe_dig("itunes_subtitle").clean
  json.summary      @feed.options&.safe_dig("itunes_summary").clean
  json.categories do
    json.array! @feed.options&.safe_dig("itunes_categories").clean
  end
end

json.items @feed.entries.order(published: :desc) do |entry|
  json.id             entry.id
  json.title          entry.try(:title).clean(transform: [:to_plain_text])
  json.url            entry.try(:url).clean
  json.date_published entry.published.iso8601(6)

  json.attachment do
    json.url           entry.data&.safe_dig("enclosure_url").clean
    json.mime_type     entry.data&.safe_dig("enclosure_type").clean
    json.size_in_bytes entry.data&.safe_dig("enclosure_length").clean(transform: :to_i)
  end

  json.podcast do
    json.author           entry.data&.safe_dig("itunes_author").clean
    json.block            entry.data&.safe_dig("itunes_block").clean
    json.closed_captioned entry.data&.safe_dig("itunes_closed_captioned").clean
    json.duration         entry.data&.safe_dig("itunes_duration").clean
    json.explicit         entry.data&.safe_dig("itunes_explicit").clean
    json.image            entry.data&.safe_dig("itunes_image").clean
    json.keywords         entry.data&.safe_dig("itunes_keywords").clean
    json.order            entry.data&.safe_dig("itunes_order").clean
    json.summary          entry.data&.safe_dig("itunes_subtitle").clean(transform: :to_plain_text) || entry.summary
    json.content          entry.content.clean
    json.chapter_titles   entry.chapter_titles.map(&:clean)
  end
end