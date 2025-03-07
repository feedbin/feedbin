class Subscriptions::NewView < ApplicationView
  def initialize(feeds:, tag_editor:, search:)
    @feeds = feeds
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

  def feed_row(feed, index, form_builder)
    div(class: "mb-4", data: { behavior: "subscription_option" }) do
      div(class: "flex items-center mb-2") do
        div(class: ["self-stretch", ("hide" if @feeds.length == 1)] do
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
      div class: ["text-500", ("pl-[28px]" if @feeds.length > 1)] do
        render App::FeedStatsComponent.new(feed: feed, stats: FeedStat.daily_counts(feed_ids: @feeds.map(&:id)))
      end
    end
  end
end