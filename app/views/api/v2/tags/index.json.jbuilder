json.array!(@tags) do |tag|
  json.partial! "api/v2/tags/tag", tag: tag
end
