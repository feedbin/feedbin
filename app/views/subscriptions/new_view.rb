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
      div(class: "flex items-center gap-2 mb-1") do
        if @search
          render FaviconComponent.new(feed: feed)
        end
        div(class: "grow") do
          render Form::TextInputComponent.new do |input|
            input.input do
              form_builder.text_field :title, placeholder: feed.title, class: "peer text-input"
            end
          end
        end
        div(class: tokens("ml-2", -> { @feeds.length == 1 } => "hide")) do
          form_builder.check_box :subscribe, checked: index == 0 ? true : false, class: "peer", data: { behavior: "check_toggle" }
          form_builder.label :subscribe, class: "group" do
            render Form::SwitchComponent.new
          end
        end
      end
      div class: tokens("pr-[50px]", -> { @search } => "pl-[30px]") do
        if feed.meta_description
          p(class: "text-sm text-600 two-lines", title: feed.meta_description) do
            feed.meta_description
          end
        end
        p(class: "text-sm text-500 truncate", title: "Feed URL") do
          helpers.pretty_url(feed.feed_url)
        end
      end
    end
  end
end