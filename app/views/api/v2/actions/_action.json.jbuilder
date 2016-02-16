json.extract! action, :id, :title, :action_type, :actions, :query, :feed_ids
json.feed_ids action.feed_ids&.map(&:to_i) || []
json.tag_ids action.tag_ids || []
