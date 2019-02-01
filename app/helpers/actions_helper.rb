module ActionsHelper
  def action_feed_names(action)
    output = []

    user = User.find(action.user_id)

    feed_names = user.feeds.where(id: action.feed_ids).include_user_title.map { |feed|
      feed.title
    }

    feed_names.sort!

    output << feed_names.shift(2).join(", ")

    if feed_names.present?
      output << "and #{feed_names.length} more feeds"
    end

    output.join(" ")
  end

  def action_tag_names(action)
    Tag.where(id: action.tag_ids).order(name: :asc).pluck(:name).join(", ")
  end

  def action_names(action)
    actions = []
    action.actions.each do |action_name|
      if action_name.present?
        actions << action_label(action_name)
      end
    end
    if actions.present?
      actions.join(" and ")
    else
      "do nothing"
    end
  end

  def action_label(value)
    action_label = ""
    Feedbin::Application.config.action_names.each do |action_name|
      if action_name.value == value
        action_label = action_name.label.downcase
      end
    end
    action_label
  end
end
