class Subscriptions::NewView < ApplicationView
  def initialize(feeds:, tag_editor:, search:)
    @feeds = feeds
    @stats = FeedStat.daily_counts(feed_ids: @feeds.map(&:id))
    @tag_editor = tag_editor
    @search = search
    @valid_feed_ids = Rails.application.message_verifier(:valid_feed_ids).generate(@feeds.map(&:id))
  end

  def view_template
    form_tag(subscriptions_path, method: :post, remote: true, data: { behavior: "subscription_options" }) do
      hidden_field_tag "valid_feed_ids", @valid_feed_ids

      render Settings::H2Component.new do
        "Feed".pluralize(@feeds.length)
      end

      div(class: "mb-12") do
        @feeds.each_with_index do |feed, index|
          fields_for "feeds[]", feed do |form_builder|
            feed_row(feed, index, form_builder)
          end
        end
      end

      render Settings::H2Component.new do
        "Tags"
      end
      render "shared/tag_fields", tag_editor: @tag_editor
      submit_tag("Submit", class: "visually-hidden", tabindex: "-1", data: { behavior: "submit_add" })
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
        div class: "flex gap-4 items-baseline" do
          p(class: "grow text-sm truncate", title: feed.feed_url) do
            helpers.display_url(feed.feed_url)
          end
          div class: "" do
            Sparkline(sparkline: ::Sparkline.new(width: 80, height: 15, stroke: 2, percentages: @stats[feed.id].percentages), theme: true)
          end
        end

        div class: "flex gap-4 items-baseline text-xs mt-1" do
          p(class: "truncate grow min-w-0", title: feed.feed_description) do
            feed.feed_description
          end
          p(class: "shrink-0") do
            plain helpers.timeago(feed.last_published_entry, prefix: "Latest article:")
            plain ", #{helpers.number_with_delimiter(@stats[feed.id].volume)}/mo"
          end
        end
      end
    end
  end
end