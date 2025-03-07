class CopyableComponent < ApplicationComponent
  def initialize(data:)
    @data = data
  end

  def view_template(&block)
    span data: stimulus(controller: :copyable, values: {data: @data}) do
      button class: "flex items-center gap-2 group focus-border", data: stimulus_item(actions: {click: :copy}, for: :copyable) do
        span &block
        span class: "relative flex flex-center size-[20px] rounded", title: "Copy", data: {toggle: "tooltip"} do
          Icon("icon-copy", class: "fill-500 group-active:fill-700 relative top-[-0.5px] right-[-0.5px]")
        end
      end

    end
  end
end
