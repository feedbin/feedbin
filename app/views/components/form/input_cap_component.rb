module Form
  class InputCapComponent < ApplicationComponent

    def initialize(position: nil)
      @position = position || "leading"
    end

    def template(&block)
      div data: {position: @position}, class: "group border border-400 inset-y-0 flex items-stretch shadow-one relative data-[position=leading]:rounded-l-md data-[position=trailing]:rounded-r-md data-[position=leading]:border-r-0 data-[position=trailing]:border-l-0" do
        yield
      end
    end
  end
end
