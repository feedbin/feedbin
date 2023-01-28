class Settings::ButtonRowComponent < BaseComponent
  def call
    content_tag :div, content, class: "flex gap-4 mt-8 justify-end"
  end
end
