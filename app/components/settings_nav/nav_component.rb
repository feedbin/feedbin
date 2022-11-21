# frozen_string_literal: true

class SettingsNav::NavComponent < BaseComponent
  def initialize(title:, subtitle: nil, url:, icon:, selected: false, classes: nil)
    @title = title
    @subtitle = subtitle
    @url = url
    @icon = icon
    @selected = selected
    @classes = classes
  end

  def before_render
    defaults = {
      class: "flex gap-2 p-2 rounded group !text-600 hover:no-underline hover:bg-200 data-selected:bg-blue-600",
      data: { ui: class_names(selected: @selected) }
    }

    @url = [*@url]
    if @url.length == 2
      options = @url.last
      defaults = defaults.reverse_merge(options)
    end

    @url[1] = defaults
  end
end
