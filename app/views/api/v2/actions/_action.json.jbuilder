feed_ids = action.user.subscriptions.where(feed_id: action.feed_ids).pluck(:feed_id)
json.extract! action, :id, :title, :action_type, :actions, :query, :feed_ids
json.feed_ids feed_ids
json.tag_ids action.tag_ids || []
