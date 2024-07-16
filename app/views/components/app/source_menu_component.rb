module App
  class SourceMenuComponent < ApplicationComponent
    def initialize(feed:, source_target:)
      @feed = feed
      @source_target = source_target
    end
    def view_template
      form( class: "feed-action-form source-menu-form", data_behavior: "feed_action_parent null_form", data_remote: "true" ) do
        button( type: "submit", class: "feed-action-button source-menu", data_behavior: "feed_action toggle_source_menu" ) do
          render SvgComponent.new("icon-dots")

          template_tag do
            ul class: "nav" do
              li do
                button data: {behavior: "menu_mark_read", source_target: @source_target} do
                  span class: "icon-wrap" do
                    render SvgComponent.new("menu-icon-mark-read")
                  end
                  span class: "menu-text" do
                    span class: "title" do
                      "Mark as read"
                    end
                  end
                end
              end

              li do
                a href: helpers.edit_subscription_path(@feed, app: true), data: {behavior: "open_settings_modal feed_settings close_source_menu", remote: true} do
                  span class: "icon-wrap" do
                    render SvgComponent.new("menu-icon-edit")
                  end
                  span class: "menu-text" do
                    span class: "title" do
                      "Edit"
                    end
                  end
                end
              end

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
                  form_with url: helpers.toggle_mute_subscription_path(@feed), method: :patch, data: {remote: true} do |form|
                    form.submit type: "submit", class: "ui-helper-hidden-accessible", tabindex: "-1"
                  end
                end
              end

              li do
                button data: {behavior: "source_menu_unsubscribe"} do
                  span class: "icon-wrap" do
                    render SvgComponent.new("menu-icon-delete")
                  end
                  span class: "menu-text" do
                    span class: "title" do
                      "Unsubscribe"
                    end
                  end
                  form_with url: helpers.destroy_from_feed_subscription_path(@feed), method: :delete, data: {behavior: "unsubscribe", remote: true, feed_id: @source_target} do |form|
                    form.submit type: "submit", class: "ui-helper-hidden-accessible", tabindex: "-1"
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
