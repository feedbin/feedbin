# frozen_string_literal: true

class SettingsNav::NavComponent < BaseComponent
  def initialize(title:, subtitle:, url:, icon:, selected: false, classes: nil)
    @title = title
    @subtitle = subtitle
    @url = url
    @icon = icon
    @selected = selected
    @classes = classes
  end
end
