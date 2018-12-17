module SettingsHelper
  def timeago(time)
    if time.nil?
      "N/A"
    else
      content_tag(:time, time.to_s(:feed), datetime: time.utc.iso8601, class: "timeago", title: "Last updated: #{time.to_s(:feed)}") + " ago"
    end
  end

  def get_tag_names(tags, feed_id)
    if names = tags[feed_id]
      names.join(", ")
    end
  end

  def tag_options
    tags = @user.feed_tags.map do |tag|
      [tag.name, tag.name]
    end
    tags.unshift ["None", ""]
  end
end
