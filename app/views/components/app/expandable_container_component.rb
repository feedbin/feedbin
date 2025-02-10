module App
  class ExpandableContainerComponent < ApplicationComponent
    def initialize(selector: nil, open: false, auto_open: false)
      @stimulus_controller = :expandable
      @selector = selector
      @open = open
      @auto_open = auto_open
    end

    def view_template(&block)
      div class: "group", data: stimulus(controller: @stimulus_controller, values: { open: @open.to_s, visible: @open.to_s, auto_open: @auto_open.to_s }, data: {@selector.to_s.to_sym => @selector.present?}), &block
    end

    def content(&block)
      div data: stimulus_item(target: :transition_container, for: @stimulus_controller), class: "#{default_rows} grid group-data-[expandable-open-value=true]:[grid-template-rows:1fr] transition-[grid-template-rows] duration-200 ease-out overflow-hidden group-data-[expandable-visible-value=true]:overflow-visible" do
        div class: "min-h-0 transition opacity-50 group-data-[expandable-open-value=true]:opacity-100 duration-500 max-h-dvh group-data-[expandable-visible-value=true]:max-h-max", &block
      end
    end

    def default_rows
      @auto_open ? "[grid-template-rows:1fr] sm:[grid-template-rows:0fr]" : "[grid-template-rows:0fr]"
    end
  end
end
