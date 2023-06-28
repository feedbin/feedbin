module Settings
  class H2Component < ApplicationComponent
    def template(&)
      h2(class: "mb-4 text-700 font-bold", &)
    end
  end
end
