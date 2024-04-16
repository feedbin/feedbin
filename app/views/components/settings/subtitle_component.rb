module Settings
  class SubtitleComponent < ApplicationComponent
    def view_template(&)
      p class: "mb-8 -mt-6 text-500", &
    end
  end
end
