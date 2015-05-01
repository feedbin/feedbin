json.array!(@entries) do |entry|
  json.partial! "api/v2/entries/entry_private", entry: entry
end
