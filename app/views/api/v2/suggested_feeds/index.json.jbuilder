json.array!(@suggested_feeds) do |suggested_feed|
  json.partial! "api/v2/suggested_feeds/suggested_feed", suggested_feed: suggested_feed
end
