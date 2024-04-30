json.extract! playlist, :id, :title, :sort_order
json.created_at playlist.created_at.iso8601(6)
json.updated_at playlist.updated_at.iso8601(6)
