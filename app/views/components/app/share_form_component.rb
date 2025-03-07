module App
  class ShareFormComponent < ApplicationComponent

    def initialize(icon:, title:)
      @icon = icon
      @title = title
    end

    def view_template
      div(class: "flex items-center gap-2 mb-4") do
        h2(class: "font-bold") { @title }
        Icon(@icon, class: "ml-auto")
      end

      yield
    end
  end
end
