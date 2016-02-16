json.array!(@entries) do |entry|
  json.partial! "api/v2/entries/entry", entry: entry
end
