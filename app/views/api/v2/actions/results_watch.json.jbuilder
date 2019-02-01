json.array!(@entries) do |entry|
  json.partial! "api/v2/entries/watch", entry: entry
end
