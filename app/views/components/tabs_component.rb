class TabsComponent < ApplicationComponent
  include Phlex::DeferredRender

  def initialize
    @tabs = []
  end

  def template
    div data: stimulus(controller: :tabs) do
      div class: "flex gap-2 border-b border-400 items-baseline mb-8" do
        @tabs.each_with_index do |tab, index|
          button class: "tab", data: button_data(index) do
            tab[:title]
          end
        end
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
