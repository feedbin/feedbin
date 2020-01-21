class UserPresenter < BasePresenter
  presents :user
  delegate_missing_to :user

  def settings
    @settings ||= JSON.parse(@template.cookies.permanent.signed[:settings]) rescue {}
  end

  def entry_width
    settings["entry_width"] || user.entry_width || "fixed"
  end

  def font
    settings["font"] || user.font || "default"
  end

  def font_size
    settings["font_size"] || user.font_size || "5"
  end

  def theme
    settings["theme"] || user.theme || "day"
  end

  def view_mode
    settings["view_mode"] || "view_unread"
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

  def resizable(column)
    widths = settings["column_widths"] || {}
    template = 'data-resizable-name="%s"'
    replacements = [column]
    if width = widths[column]
      template << ' style="width: %ipx"'
      replacements << width.to_i
    end
    result = template % replacements
    result.html_safe
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
        array << entry_width
        array << "entries-body-#{entries_body}"
        array << "entries-time-#{entries_time}"
        array << "entries-feed-#{entries_feed}"
        array << "entries-image-#{entries_image}"
        array << "entries-display-#{entries_display}"
        array << "setting-view-link-#{view_links_in_app}"
      end.flatten.join(" ")
    end
  end

  def content_classes
    @content_classes ||= begin
      [].tap do |array|
        array << entry_width
        array << display_prefs
      end.flatten.join(" ")
    end
  end

end
