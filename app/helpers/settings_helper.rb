module SettingsHelper
  def timeago(time)
    if time.nil?
      'N/A'
    else
      content_tag(:time, time.to_s(:feed), datetime: time.utc.iso8601, class: 'timeago' )
    end
  end
end
