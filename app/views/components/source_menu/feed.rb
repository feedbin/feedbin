module SourceMenu
  class Feed < ApplicationComponent
    def initialize(feed:, source_target:)
      @feed = feed
      @source_target = source_target
    end

    def view_template
      render(Wrapper.new) do
        render ActionMarkRead.new(source_target: @source_target)
        render ActionEdit.new(href: edit_subscription_path(@feed, app: true))

        li do
          button data: {behavior: "source_menu_mute", feed_id: @source_target} do
            span class: "icon-wrap" do
              render SvgComponent.new("menu-icon-mute")
            end
            span class: "menu-text" do
              span class: "title" do
                "Mute"
              end
            end
            form_with url: toggle_mute_subscription_path(@feed), method: :patch, local: false do |form|
              form.submit type: "submit", class: "ui-helper-hidden-accessible", tabindex: "-1"
            end
          end
        end

        li do
          button data: {behavior: "source_menu_unsubscribe", message: "Are you sure you want to unsubscribe?"} do
            span class: "icon-wrap" do
              render SvgComponent.new("menu-icon-delete")
            end
            span class: "menu-text" do
              span class: "title" do
                "Unsubscribe"
              end
            end
            form_with url: destroy_from_feed_subscription_path(@feed), method: :delete, local: false, data: {behavior: "unsubscribe", feed_id: @source_target} do |form|
              form.submit type: "submit", class: "ui-helper-hidden-accessible", tabindex: "-1"
            end
          end
        end
      end
    end
  end
end
