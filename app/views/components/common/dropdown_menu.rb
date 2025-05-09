class Common::DropdownMenu < ApplicationComponent
  include DeferredRender

  def initialize
    @items = []
  end

  def view_template
    div class: "dropdown-wrap dropdown-right" do
      button data_behavior: "toggle_dropdown" do
        Icon("menu-icon-menu", class: "fill-500")
      end
      div class: "dropdown-wrap" do
        div class: "dropdown-content" do
          ul class: "nav" do
            @items.each { render it }
          end
        end
      end
    end
  end

  def item(...)
    @items << Item.new(...)
  end

  class Item < ApplicationComponent
    def initialize(icon:, title:, subtitle: nil, type: :button, attributes: {})
      @icon = icon
      @title = title
      @attributes = attributes
      @subtitle = subtitle
      @type = type
    end

    def view_template
      li do
        send @type, **@attributes do
          span class: "icon-wrap" do
            Icon(@icon)
          end
          span class: "menu-text" do
            span class: "title" do
              @title
            end
          end
        end
      end
    end
  end

end
