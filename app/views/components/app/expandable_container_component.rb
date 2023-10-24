module App
  class ExpandableContainerComponent < ApplicationComponent
    def initialize(selector: nil, open: false)
      @stimulus_controller = :expandable
      @selector = selector
      @open = open
    end

    def template(&)
      div class: "group", data: stimulus(controller: @stimulus_controller, values: { open: @open.to_s, visible: @open.to_s }, data: {@selector.to_s.to_sym => "true"}), &
    end

    def content(&)
      render ContentComponent.new(stimulus_controller: @stimulus_controller, open: @open, &)
    end

    class ContentComponent < ApplicationComponent
      def initialize(stimulus_controller:, open:)
        @stimulus_controller = stimulus_controller
        @open = open
      end

      def template(&)
        div data: stimulus_item(target: :transition_container, for: @stimulus_controller), class: "grid [grid-template-rows:0fr] group-data-[expandable-open-value=true]:[grid-template-rows:1fr] transition-[grid-template-rows] duration-200 overflow-hidden group-data-[expandable-visible-value=true]:overflow-visible" do
          div class: "min-h-0 transition opacity-0 group-data-[expandable-open-value=true]:opacity-100 duration-500", &
        end
      end
    end
  end
end
