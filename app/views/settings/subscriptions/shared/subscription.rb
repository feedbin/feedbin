module Settings
  module Subscriptions
    module Shared
      class Subscription < ApplicationComponent

        def initialize(subscription:)
          @subscription = subscription
        end

        def view_template
          view_context.present @subscription do |subscription_presenter|
            fields_for "subscriptions[]", @subscription do |f|
              li class: "flex items-center relative border-b" do
                div class: "shrink-0 w-[32px] self-stretch flex" do
                  check_box_tag "subscription_ids[]", @subscription.id, false, id: "subscription_checkbox_#{@subscription.id}", class: "peer", data: {action: "toggle-checkboxes#toggleActions", toggle_checkboxes_target: "checkbox"}
                  label class: "group w-full h-full flex items-center", for: "subscription_checkbox_#{@subscription.id}" do
                    render Form::CheckboxComponent.new
                  end
                end

                link_to edit_settings_subscription_path(@subscription), class: "flex grow items-center overflow-hidden gap-3 py-3 !text-600 hover:no-underline" do
                  span class: "block" do
                    raw subscription_presenter.favicon(@subscription.feed)
                  end
                  span class: "truncate" do
                    span class: "block truncate" do
                      plain @subscription.title
                    end
                    span class: "block truncate !text-500 text-sm", title: @subscription.feed_url do
                      plain display_url(@subscription.feed_url)
                    end
                  end
                  span class: "ml-auto flex items-center gap-4" do
                    status_icon(subscription_presenter)
                    Icon("icon-caret", class: "fill-300 -rotate-90")
                  end
                end
              end
            end
          end
        end

        def status_icon(subscription_presenter)
          if @subscription.fixable?
            span class: "w-[16px] h-[16px] flex flex-center" do
              Icon("menu-icon-fix-feeds", class: "fill-600", title: "Fixable feed", data: {toggle: "tooltip"})
            end
          elsif @subscription.dead?
            span class: "w-[16px] h-[16px] flex flex-center" do
              Icon("menu-icon-skull", class: "fill-600", title: "Error crawling feed", data: {toggle: "tooltip"})
            end
          elsif @subscription.muted?
            span class: "w-[16px] h-[16px] flex flex-center" do
              Icon("menu-icon-mute", class: "fill-600", title: "Muted", data: {toggle: "tooltip"})
            end
          else
            div class: "flex flex-col gap-2 items-end" do
              Sparkline(sparkline: subscription_presenter.sparkline, theme: false)
              div class: "text-500 text-sm whitespace-nowrap" do
                timeago(@subscription.last_published_entry, prefix: "Latest article:")
                plain ", #{number_with_delimiter(@subscription.post_volume)}/mo"
              end
            end
          end
        end
      end
    end
  end
end
