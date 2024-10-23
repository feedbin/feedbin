class UserPresenter < BasePresenter
  presents :user
  delegate_missing_to :user

  def settings
    @settings ||= begin
                    JSON.parse(@template.cookies.permanent.signed[:settings])
                  rescue
                    {}
                  end
  end

  def entry_width
    result = settings["entry_width"].present? ? settings["entry_width"] : nil
    result = result || user.entry_width || "fixed"
    if result == "fluid"
      result = "1"
    elsif result == ""
      result = "0"
    end
    result
  end

  def font
    result = settings["font"].present? ? settings["font"] : nil
    result || user.font || "default"
  end

  def font_size
    result = settings["font_size"].present? ? settings["font_size"] : nil
    result || user.font_size || "5"
  end

  def theme
    result = settings["theme"].present? ? settings["theme"] : nil
    result || user.theme || "auto"
  end

  def view_mode
    result = settings["view_mode"].present? ? settings["view_mode"] : nil
    result || "view_unread"
  end

  def entries_display
    user.entries_display || "block"
  end

  def entries_feed
    user.entries_feed || "1"
  end

  def entries_time
    user.entries_time || "1"
  end

  def entries_body
    user.entries_body || "1"
  end

  def entries_image
    user.entries_image || "1"
  end

  def view_links_in_app
    user.view_links_in_app || "0"
  end

  def feeds_width
    settings["feeds_width"] || nil
  end

  def entries_width
    settings["entries_width"] || nil
  end

  def feeds_width_style
    width = feeds_width.try(:to_i)
    if width.present? && width != 0
      "width: #{width}px;"
    end
  end

  def entries_width_style
    width = entries_width.try(:to_i)
    if width.present? && width != 0
      "width: #{width}px;"
    end
  end

  def display_prefs
    @display_prefs ||= begin
      [].tap do |array|
        array << "font-size-#{font_size}"
        array << "font-#{font}"
      end.join(" ")
    end
  end

  def setting_classes
    @setting_classes ||= begin
      [].tap do |array|
        array << "theme-" + theme
        array << view_mode
        array << "fluid-#{entry_width}"
        array << "entries-body-#{entries_body}"
        array << "entries-time-#{entries_time}"
        array << "entries-feed-#{entries_feed}"
        array << "entries-image-#{entries_image}"
        array << "entries-display-#{entries_display}"
        array << "setting-view-link-#{view_links_in_app}"
        array << "feature-flag-floaty-#{user.floaty.to_s}"
      end.flatten.join(" ")
    end
  end

  def content_classes
    @content_classes ||= begin
      [].tap do |array|
        array << "fluid-#{entry_width}"
        array << display_prefs
      end.flatten.join(" ")
    end
  end
end
