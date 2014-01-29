module SettingsHelper
  def timeago(time)
    content_tag(:time, time.to_s(:feed), datetime: time.utc.iso8601, class: 'timeago' )
  end
end
