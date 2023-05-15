json.extract! queued_entry, :id, :entry_id, :feed_id, :playlist_id, :order, :progress
json.created_at queued_entry.created_at.iso8601(6)
json.updated_at queued_entry.updated_at.iso8601(6)
