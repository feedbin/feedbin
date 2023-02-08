class Settings::H2Component < BaseComponent
  def call
    content_tag :h2, content, class: "mb-4 text-700 font-bold"
  end
end
