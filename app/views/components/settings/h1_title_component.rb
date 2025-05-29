module Settings
  class H1TitleComponent < ApplicationComponent
    def view_template(&)
      h1(class: "max-sm:truncate mt-10 mb-8 mr-5 md:mr-0 font-bold text-2xl text-700", &)
    end
  end
end
