module FixFeeds
  class SuggestionComponent < ApplicationComponent

    def initialize(replaceable:, source:, redirect:, remote: true, include_ignore: false)
      @replaceable = replaceable
      @source = source
      @redirect = redirect
      @remote = remote
      @include_ignore = include_ignore
    end

    def view_template
      div(class: "items-start") do
        header
        form
      end
    end

    def header
      div class: "mb-4 grow" do
        render App::FeedComponent do |feed|
          feed.icon do
            favicon_with_record(@source.favicon, host: @source.host, generated: true)
          end
          feed.title do
            link_to(@source.site_url, target: :blank, class: "!text-600") do
              span(data_behavior: "user_title", class: "truncate") do
                @replaceable.title
              end
            end
          end
          feed.subhead do
            link_to(@source.feed_url, target: :blank, class: "!text-500 truncate") do
              short_url_alt(@source.feed_url)
            end
          end

          feed.accessory do
            div class: "bg-orange-600 h-[16px] w-[16px] rounded-full flex flex-center", title: @source.crawl_error_message, data: {toggle: "tooltip"} do
              Icon("icon-exclamation", class: "fill-white")
            end

            if @source.last_published_entry.respond_to?(:to_formatted_s)
              plain "Last worked: "
              plain @source.last_published_entry&.to_formatted_s(:month_year)
            end
          end

        end
      end
    end

    def form
      form_with(model: @replaceable, url: @replaceable.replaceable_path, data: {remote: @remote, behavior: "disable_on_submit"}, class: "ml-[30px]") do |form|
        form.hidden_field :redirect_to, value: @redirect
        render Settings::ControlGroupComponent.new class: "group", data: {item_capsule: "true"} do |group|
          discovered_feeds = @source.discovered_feeds.order(created_at: :asc)
          discovered_feeds.each_with_index do |discovered_feed, index|
            group.item do
              div class: "grow #{index != 0 ? "mt-[8px]" : ""}" do
                suggestion(discovered_feed: discovered_feed, checked: index == 0, show_radio: @source.discovered_feeds.count > 1)
              end
            end
          end
        end

        div(class: "flex gap-4 pt-4 justify-end") do
          if @replaceable.respond_to?(:destroyable_path)
            link_to "Unsubscribe", @replaceable.destroyable_path, method: :delete, remote: true, class: "button-tertiary mr-auto", data: stimulus_item(actions: {click: :toggle}, for: :expandable)
          end

          if @include_ignore
            link_to "Ignore", @replaceable.replaceable_path, method: :delete, remote: true, class: "button-tertiary", data: stimulus_item(actions: {click: :toggle}, for: :expandable)
          end

          button class: "button-secondary", type: "submit", data: stimulus_item(actions: {click: :toggle}, for: :expandable) do
            "Replace Feed"
          end
        end
      end
    end

    def suggestion(discovered_feed:, checked:, show_radio:)
      fields_for :discovered_feed, discovered_feed do |discovered_feed_form|
        discovered_feed_form.radio_button(:id, discovered_feed.id, checked: checked, class: "peer")
        discovered_feed_form.label :id, value: discovered_feed.id, class: "group" do
          render Settings::ControlRowComponent.new do |row|
            row.content do
              render App::FeedComponent do |feed|
                feed.title do
                  link_to(discovered_feed.site_url, target: :blank, class: "!text-600 font-bold") do
                    discovered_feed.title
                  end
                end
                feed.subhead do
                  link_to(discovered_feed.feed_url, class: "!text-green-600 truncate", target: :blank) do
                    short_url_alt(discovered_feed.feed_url)
                  end
                end
              end
            end

            row.control do
              if show_radio
                render Form::RadioComponent.new
              end
            end
          end
        end
      end
    end
  end
end
