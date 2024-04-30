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
        div class: "flex gap-4" do
          div class: "flex inset-y-0 self-stretch" do
            render Timeline.new(color: "bg-orange-600", options: {first: true}, tooltip: @source.crawl_error_message) do
              render SvgComponent.new("icon-exclamation", class: "fill-white")
            end
          end

          header
        end

        form
      end
    end

    def header
      div class: "p-4 grow border border-transparent" do
        render App::FeedComponent do |feed|
          feed.icon do
            helpers.favicon_with_record(@source.favicon, host: @source.host, generated: true)
          end
          feed.title do
            link_to(@source.site_url, target: :blank, class: "!text-600") do
              span(data_behavior: "user_title", class: "truncate") do
                @replaceable.title
              end
            end
          end
          feed.subhead do
            link_to(@source.feed_url, class: "!text-500 truncate", target: :blank) do
              helpers.short_url_alt(@source.feed_url)
            end
          end

          if @source.last_published_entry.respond_to?(:to_formatted_s)
            feed.accessory do
              plain "Last worked: "
              plain @source.last_published_entry&.to_formatted_s(:month_year)
            end
          end
        end
      end
    end

    def form
      form_with(model: @replaceable, url: @replaceable.replaceable_path, data: {remote: @remote, behavior: "disable_on_submit"}) do |form|
        form.hidden_field :redirect_to, value: @redirect
        render Settings::ControlGroupComponent.new class: "group", data: {item_capsule: "true"} do |group|
          discovered_feeds = @source.discovered_feeds.order(created_at: :asc)
          discovered_feeds.each_with_index do |discovered_feed, index|
            group.item do
              div class: "flex gap-4" do
                render Timeline.new(color: "bg-green-600", options: {last: discovered_feed == discovered_feeds.last, middle: index != 0}) do
                  render SvgComponent.new("icon-check-small", class: "fill-white")
                end

                div class: "grow #{index != 0 ? "mt-[8px]" : ""}" do
                  suggestion(discovered_feed: discovered_feed, checked: index == 0, show_radio: @source.discovered_feeds.count > 1)
                end
              end
            end
          end
        end

        div(class: "flex gap-4 pt-4 justify-end") do
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
                feed.icon do
                  helpers.favicon_with_host(discovered_feed.host, generated: true)
                end
                feed.title do
                  link_to(discovered_feed.site_url, target: :blank, class: "!text-600 font-bold") do
                    discovered_feed.title
                  end
                end
                feed.subhead do
                  link_to(discovered_feed.feed_url, class: "!text-500 truncate", target: :blank) do
                    helpers.short_url_alt(discovered_feed.feed_url)
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


    class Timeline < ApplicationComponent
      def initialize(color:, options: {}, tooltip: nil)
        @options = options
        @color = color
        @tooltip = tooltip
      end

      def view_template
        div class: "flex flex-col items-center w-[16px] inset-y-0 self-stretch shrink-0"  do
          div class: "w-[1px] shrink-0 bg-500 #{middle? ? "h-[21px]" : "h-[13px]"} #{first? ? "invisible" : ""}"
          div class: "flex w-[16px] h-[16px] flex-center my-[8px] shrink-0" do
            div class: "#{@color} h-[16px] w-[16px] rounded-full flex flex-center", title: @tooltip, data: {toggle: @tooltip.present? ? "tooltip" : ""} do
              yield
            end
          end
          div class: "h-full w-[1px] bg-500 #{last? ? "invisible" : ""}"
        end
      end

      def first?
        !!@options[:first]
      end

      def last?
        !!@options[:last]
      end

      def middle?
        !!@options[:middle]
      end
    end
  end
end
