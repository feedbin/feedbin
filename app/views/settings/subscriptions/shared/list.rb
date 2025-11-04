module Settings
  module Subscriptions
    module Shared
      class List < ApplicationComponent

        def initialize(subscriptions:, params:)
          @subscriptions = subscriptions
          @params = params
        end

        def view_template
          div data_behavior: "subscriptions_list" do
            form_tag update_multiple_settings_subscriptions_path, method: :patch, autocomplete: "off", class: "group", data: {controller: "toggle-checkboxes", toggle_checkboxes_include_all_visible_value: "false"} do |update_form|
              hidden_field_tag :q, @params[:q]
              div class: "py-3 flex border-y items-center justify-between" do
                input type: "checkbox", class: "peer", data_action: "toggle-checkboxes#toggle", id: "select_all_feeds"
                label for: "select_all_feeds", class: "group flex gap-2 items-center" do
                  render Form::CheckboxComponent.new
                  plain " Select All "
                end
                div class: "max-w-[250px]" do
                  render Form::SelectInputComponent.new do |input|
                    input.input do
                      select_tag(:operation,
                        options_for_select([["Actions", nil], ["Unsubscribe", "unsubscribe"], ["Show edits on articles", "show_updates"], ["Hide edits on articles", "hide_updates"], ["Mute Feed", "mute"], ["Unmute Feed", "unmute"]]),
                        class: "peer",
                        disabled: true,
                        data: {behavior: "feed_actions", toggle_checkboxes_target: "actions"}
                      )
                    end
                  end
                end
              end

              if @subscriptions.total_entries > @subscriptions.count
                div class: "border-b py-3 block group-data-[toggle-checkboxes-include-all-visible-value=false]:hidden" do
                  check_box_tag "include_all", 1, false, data: {action: "toggle-checkboxes#includeAll", toggle_checkboxes_target: "includeAll"}, class: "peer", id: "include_all_feeds"
                  label for: "include_all_feeds", class: "group flex gap-2 items-center" do
                    render Form::CheckboxComponent.new
                    if @params[:q]
                      plain "Include all #{number_with_delimiter(@subscriptions.total_entries)} #{"subscription".pluralize(@subscriptions.total_entries)} matching this search"
                    else
                      plain "Include all #{number_with_delimiter(@subscriptions.total_entries)} #{"subscription".pluralize(@subscriptions.total_entries)}"
                    end
                  end
                end
              end

              ul class: "mb-14" do
                @subscriptions.each do |subscription|
                  render Subscription.new(subscription: subscription)
                end
              end

              raw will_paginate @subscriptions, previous_label: "Previous", next_label: "Next", inner_window: 1
            end
          end
        end
      end
    end
  end
end
