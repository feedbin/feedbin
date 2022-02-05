json.array!(@queued_entries) do |queued_entry|
  json.partial! "queued_entry", queued_entry: queued_entry
end
