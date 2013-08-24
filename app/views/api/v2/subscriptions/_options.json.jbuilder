json.array!(options) do |option|
  json.feed_url option[:href]
  json.title option[:title]
end