module Dialog
  class AddFeed < ApplicationComponent
    TITLE = "Add Feed"
    STIMULUS_CONTROLLER = :add_feed

    def initialize(query: "")
      @query = query
    end

    def view_template
      controller = stimulus(
        controller: STIMULUS_CONTROLLER,
        values: {count: 0, selected: 0},
        actions: {
          "add-feed:updateContent@window" => "updateContent",
          "add-feed:clearResults@window" => "clearResults",
        }
      )
      render Dialog::Template::Wrapper.new(dialog_id: self.class.dom_id) do
        div class: "group", data: controller do
          render Dialog::Template::InnerContent.new do |dialog|
            dialog.title do
              TITLE
            end

            dialog.body do
              form_with url: search_feeds_path, data: stimulus_item(target: :search_form, actions: {submit: :clearResults}, data: { remote: true, behavior: "spinner" }, for: STIMULUS_CONTROLLER), html: { autocomplete: "off", novalidate: true, class: "group" } do
                render Form::TextInputComponent.new do |text|
                  text.input do
                    search_field_tag :q, @query, placeholder: "Search or URL", autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: false, autofocus: true, data: stimulus_item(target: :search_input, data: { behavior: "autofocus" }, for: STIMULUS_CONTROLLER)
                  end
                  text.accessory_leading do
                    render SvgComponent.new "favicon-search", class: "ml-2 fill-400 pg-focus:fill-blue-600"
                  end
                  text.accessory_trailing do
                    div class: "mx-2" do
                      render App::SpinnerComponent.new
                    end
                  end
                end
              end

              div class: "transition-[height] duration-200 ease-out", data: stimulus_item(target: :results_body, for: STIMULUS_CONTROLLER)
            end

            dialog.footer do
              div data: stimulus_item(target: :results_footer, for: STIMULUS_CONTROLLER)
            end
          end
        end
      end
    end

    class ResultsData < ApplicationComponent
      component_options skip_comment: true

      def initialize(query:, feeds:, tag_editor:, search:, basic_auth:, auth_attempted:)
        @query = query
        @feeds = feeds
        @tag_editor = tag_editor
        @search = search
        @basic_auth = basic_auth
        @auth_attempted = auth_attempted
      end

      def view_template
        unsafe_raw(
          JSON.generate({
            body: capture { body },
            footer: capture { footer },
          }, script_safe: true)
        )
      end

      def body
        div class: "animate-fade-in mt-4" do
          if @basic_auth
            auth
          else
            feeds
          end
        end
      end

      def auth
        form_tag({ controller: "feeds", action: "search" }, id: "add_form", method: :post, remote: true, data: stimulus_item(actions: {submit: :clearResults}, for: STIMULUS_CONTROLLER)) do
          hidden_field_tag :q, @query

          p class: "text-sm text-500 mb-4"  do
            "This feed is protected. Enter your username and password to continue."
          end

          div class: "mb-4" do
            render Form::TextInputComponent.new do |text|
              text.label { label_tag :basic_username, "Username" }
              text.input do
                text_field_tag :username, "", id: "basic_username", class: "peer text-input"
              end
            end
          end

          render Form::TextInputComponent.new do |text|
            text.label { label_tag :basic_password, "Password" }
            text.input do
              password_field_tag :password, "", id: "basic_password", class: "peer text-input"
            end
          end

          if @auth_attempted
            p class: "text-red-600 mt-2 text-center" do
              "Invalid username or password."
            end
          end
        end
      end

      def feeds
        form_tag(subscriptions_path, method: :post, remote: true, id: "add_form", data: { behavior: "subscription_options close_dialog_on_submit" }) do
          hidden_field_tag "valid_feed_ids", valid_feed_ids

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
        end
      end

      def feed_row(feed, index, form_builder)
        div(class: "mb-4", data: { behavior: "subscription_option" }) do
          div(class: "flex items-center mb-2") do
            div(class: tokens("self-stretch", -> { @feeds.length == 1 } => "hide")) do
              form_builder.check_box :subscribe, checked: index == 0 ? true : false, class: "peer", data: stimulus_item(target: :checkbox, actions: {change: :count_selected}, for: STIMULUS_CONTROLLER)
              form_builder.label :subscribe, class: "group flex flex-center h-full pr-3" do
                render Form::CheckboxComponent.new
              end
            end
            div(class: "grow") do
              render Form::TextInputComponent.new do |input|
                input.accessory_leading do
                  span(class: "pl-2") {render FaviconComponent.new(feed: feed)}
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

      def footer
        div class: "flex items-center group gap-2 animate-fade-in" do
          if @basic_auth
            button type: "submit", class: "ml-auto button", form: "add_form" do
              "Continue"
            end
          else
            message_class = "text-sm truncate min-w-0"
            div class: "#{message_class} tw-hidden group-data-[add-feed-selected-value=0]:block" do
              "Select one or more feeds"
            end
            div class: "#{message_class} tw-hidden group-data-[add-feed-selected-value=1]:block" do
              "Subscribe to the selected feed"
            end
            div class: "#{message_class} group-data-[add-feed-selected-value=0]:tw-hidden group-data-[add-feed-selected-value=1]:tw-hidden" do
              "Subscribe to the selected feeds"
            end

            button type: "submit", class: "ml-auto button", disabled: "disabled", form: "add_form", data: stimulus_item(target: :submit, for: STIMULUS_CONTROLLER) do
              "Add"
            end

          end
        end
      end

      def valid_feed_ids
        Rails.application.message_verifier(:valid_feed_ids).generate(@feeds.map(&:id))
      end
    end
  end
end