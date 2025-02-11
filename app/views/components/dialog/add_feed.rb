module Dialog
  class AddFeed < ApplicationComponent
    TITLE = "Add Feed"

    def initialize(query: "")
      @query = query
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end

        dialog.body do
          render SearchField.new(query: @query)
        end
      end
    end

    class Results < ApplicationComponent
      def initialize(query:, feeds:, tag_editor:, search:)
        @query = query
        @feeds = feeds
        @tag_editor = tag_editor
        @search = search
        @valid_feed_ids = Rails.application.message_verifier(:valid_feed_ids).generate(@feeds.map(&:id))
      end
      def view_template
        render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
          dialog.title do
            TITLE
          end

          dialog.body do
            div class: "mb-4" do
              render SearchField.new(query: @query)
            end

            div class: "animate-fade-in" do
              form_tag(subscriptions_path, method: :post, remote: true, data: { behavior: "subscription_options" }) do
                hidden_field_tag "valid_feed_ids", @valid_feed_ids

                render Settings::H2Component.new do
                  "Feed".pluralize(@feeds.length)
                end

                div(class: "mb-6") do
                  @feeds.each_with_index do |feed, index|
                    fields_for "feeds[]", feed do |form_builder|
                      feed_row(feed, index, form_builder)
                    end
                  end
                end

                render Settings::H2Component.new do
                  "Tags"
                end
                render App::TagFieldsComponent.new(tag_editor: @tag_editor)
                submit_tag("Submit", class: "visually-hidden", tabindex: "-1", data: { behavior: "submit_add" })
              end
            end
          end

          dialog.footer do
            div(class: "password-footer hide") do
              button type: "button", class: "button button-tertiary", data_dismiss: "modal" do
                "Cancel"
              end
              button type: "button", class: "button", data_behavior: "submit_add" do
                "Continue"
              end
            end

            div class: "subscribe-footer" do
              span data_behavior: "feeds_search_messages", class: "modal-footer-message" do
                span data_behavior: "feeds_search_message message_none", class: "hide" do
                  "Select one or more feeds"
                end
                span data_behavior: "feeds_search_message message_one", class: "hide" do
                  "Subscribe to the selected feed"
                end
                span data_behavior: "feeds_search_message message_multiple", class: "hide" do
                  "Subscribe to the selected feeds"
                end
              end

              button type: "button", class: "button", data_behavior: "submit_add", disabled: "disabled" do
                "Add"
              end
            end
          end

        end
      end

      def feed_row(feed, index, form_builder)
        div(class: "mb-4", data: { behavior: "subscription_option" }) do
          div(class: "flex items-center mb-2") do
            div(class: tokens("self-stretch", -> { @feeds.length == 1 } => "hide")) do
              form_builder.check_box :subscribe, checked: index == 0 ? true : false, class: "peer", data: { behavior: "check_toggle" }
              form_builder.label :subscribe, class: "group flex flex-center h-full pr-3" do
                render Form::CheckboxComponent.new
              end
            end
            div(class: "grow") do
              render Form::TextInputComponent.new do |input|
                if @search
                  input.accessory_leading do
                    span(class: "pl-2") {render FaviconComponent.new(feed: feed)}
                  end
                end

                input.input do
                  form_builder.text_field :title, placeholder: feed.title, class: "peer text-input"
                end
              end
            end
          end
          div class: tokens("text-500", -> { @feeds.length > 1 } => "pl-[28px]") do
            render App::FeedStatsComponent.new(feed: feed, stats: FeedStat.daily_counts(feed_ids: @feeds.map(&:id)))
          end
        end
      end

    end

    class SearchField < ApplicationComponent
      def initialize(query: "")
        @query = query
      end

      def view_template
        form_with url: search_feeds_path, data: { behavior: "feeds_search", remote: true }, html: { autocomplete: "off", novalidate: true } do

          render Form::TextInputComponent.new do |text|
            text.input do
              search_field_tag :q, @query, placeholder: "Search or URL", autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: false, autofocus: true, data: { behavior: "feeds_search_field autofocus" }
            end
            text.accessory_leading do
              render SvgComponent.new "favicon-search", class: "ml-2 fill-400 pg-focus:fill-blue-600"
            end
          end

          span data_behavior: "feeds_search_favicon_target", class: "favicon-target"

          div class: "absolute right-6 inset-y-0" do
            render App::SpinnerComponent.new
          end
        end
      end
    end
  end
end
