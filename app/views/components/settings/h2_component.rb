module Settings
  class H2Component < ApplicationComponent
    def initialize(attributes = {})
      @attributes = attributes
    end

    def template(&)
      h2(**mix({class: "mb-4 text-700 font-bold"}, @attributes), &)
    end
  end
end
