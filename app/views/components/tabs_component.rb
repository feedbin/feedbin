class TabsComponent < ApplicationComponent
  include Phlex::DeferredRender

  def initialize
    @tabs = []
  end

  def template
    div data: stimulus(controller: :tabs) do
      div class: "flex gap-8 border-b border-300 items-baseline mb-8 relative" do
        @tabs.each_with_index do |tab, index|
          button class: "inline-flex border-0 leading-[42px] text-500 data-selected:text-700", data: button_data(index) do
            tab[:title]
          end
        end
        div data: stimulus_item(target: :indicator, for: :tabs), style: "left: 0; width: 0", class: "absolute bottom-[-1px] h-[4px] w-3 bg-blue-600 transition-position duration-200 ease-in-out"
      end
      @tabs.each_with_index do |tab, index|
        div class: "tw-hidden data-selected:block", data: tab_data(index) do
          yield_content &tab[:block]
        end
      end
    end
  end

  def tab(title:, &block)
    @tabs.push({
      title: title,
      block: block
    })
  end

  def tab_data(index)
    stimulus_item(
      target: :tab_content,
      data: {ui: index == 0 ? "selected" : ""},
      for: :tabs
    )
  end

  def button_data(index)
    stimulus_item(
      target: :tab_button,
      actions: {click: :select},
      params: {tab: index},
      data: {ui: index == 0 ? "selected" : ""},
      for: :tabs
    )
  end
end
