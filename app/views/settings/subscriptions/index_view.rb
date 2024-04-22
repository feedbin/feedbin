module Settings
  module Subscriptions
    class IndexView < ApplicationView

      def initialize(user:, subscriptions:, params:)
        @user = user
        @subscriptions = subscriptions
        @params = params
      end

      def view_template
        form_tag helpers.settings_subscriptions_path, method: :get, remote: true, class: "feed-settings", data: {behavior: "spinner"} do
          render Settings::H1Component.new do
            "Subscriptions"
          end

          fix_feeds_notice

          div class: "flex flex-col md:flex-row justify-between mb-6 gap-2" do
            div class: "md:max-w-[250px]" do
              render Form::TextInputComponent.new do |input|
                input.input do
                  input(
                    type: "search",
                    class: "feed-search peer text-input",
                    placeholder: "Search Feeds",
                    data_behavior: "autosubmit",
                    name: "q",
                    value: @params[:q]
                  )
                end
                input.accessory_leading do
                  render SvgComponent.new "icon-search", class: "ml-2 fill-400 pg-focus:fill-blue-600"
                end
              end
            end
            div class: "md:max-w-[250px]" do
              render Form::SelectInputComponent.new do |input|
                input.input do
                  select_tag(
                    :sort,
                    helpers.options_for_select([["Sort by Name", "name"], ["Sort by Last Updated", "updated"], ["Sort by Volume", "volume"]], @params[:sort]),
                    class: "peer",
                    data: {behavior: "autosubmit"}
                  )
                end
              end
            end
          end
        end

        render Shared::List.new(subscriptions: @subscriptions, params: @params)
      end

      def fix_feeds_notice
        if @user.subscriptions.where(fix_status: :present).exists?
          div(class: "border rounded-lg flex gap-6 p-4 mb-8 bg-100") do
            div(class: "flex gap-4") do
              div class: "pt-1 flex flex-center shrink-0" do
                div class: "h-[32px] w-[32px] flex flex-center rounded-full bg-orange-600" do
                  render SvgComponent.new "menu-icon-fix-feeds", class: "fill-white"
                end
              end

              div(class: "grow flex gap-2 sm:gap-6 flex-col sm:flex-row sm:items-center") do
                div(class: "grow") do
                  p do
                    "Fixable Feeds"
                  end
                  p class: "text-sm text-500" do
                    "Feedbin is no longer able to download some feeds from their original source. However, there may be working alternatives available."
                  end
                end

                link_to "Review Feeds", helpers.fix_feeds_path, class: "whitespace-nowrap shrink-0"
              end
            end
          end
        end
      end
    end
  end
end