module ActionsHelper

  def action_class(persisted)
    if persisted
      'persisted'
    else
      ''
    end
  end

  def action_feed_names(action)
    if action.all_feeds
      'All'
    else
      feed_names = []
      user = User.find(action.user_id)
      feeds = user.feeds.where(id: action.feed_ids).include_user_title
      feeds.each do |feed|
        feed_names << feed.title
      end
      if feed_names.any?
        feed_names.join(', ')
      else
        'None'
      end
    end
  end

  def action_names(action)
    actions = []
    action.actions.each do |action_name|
      actions << action_label(action_name)
    end
    if actions.any?
      actions.join(', ')
    else
      'None'
    end
  end

  def action_label(value)
    action_label = ''
    Feedbin::Application.config.action_names.each do |action_name|
      if action_name.value == value
        action_label = action_name.label
      end
    end
    action_label
  end

end
