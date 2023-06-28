module Form
  class InputAccesssoryComponent < ApplicationComponent

    def initialize(position: nil)
      @position = position || "leading"
    end

    def template(&block)
      div data: {position: @position}, class: "group pointer-events-none absolute inset-y-0 flex items-center z-10 data-[position=leading]:left-0 data-[position=trailing]:right-0 data-[position=leading]:pl-3 data-[position=trailing]:pr-3" do
        yield
      end
    end
  end
end
