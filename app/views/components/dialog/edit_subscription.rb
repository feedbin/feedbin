module Dialog
  class EditSubscription < ApplicationComponent
    TITLE = "Edit Subscription"

    def initialize(subscription:, tag_editor:, stats:, app:)
      @subscription = subscription
      @tag_editor = tag_editor
      @stats = stats
      @app = app
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end
        dialog.body do
          div class: "animate-fade-in" do
            form_for(@subscription, remote: true, method: :patch, html: {data: {behavior: "close_dialog_on_submit"}}) do |form_builder|
              if @app
                hidden_field_tag :app, 1
              end
              div class: "mb-2" do
                render Form::TextInputComponent.new do |input|
                  input.accessory_leading do
                    span(class: "pl-2") {render FaviconComponent.new(feed: @subscription.feed)}
                  end
                  input.input do
                    form_builder.text_field :title, placeholder: @subscription.feed.title, class: "peer text-input"
                  end
                end
              end
              div class: "mb-6" do
                render App::FeedStatsComponent.new(feed: @subscription.feed, stats: @stats)
              end

              render App::TagFieldsComponent.new(tag_editor: @tag_editor)
            end
          end
        end
        dialog.footer do
          render Dialog::Template::FooterControls.new do
            unsubscribe_link

            button type: "submit", class: "dialog-button-primary", value: "save", form: dom_id(@subscription, :edit) do
              "Save"
            end
          end
        end
      end
    end

    def unsubscribe_link
      data = { confirm: "Are you sure you want to unsubscribe?" }
      path = settings_subscription_path(@subscription)

      if @app
        data[:feed_id] = @subscription.feed.id
        data[:behavior] = "unsubscribe close_dialog"
        path = subscription_path(@subscription)
      end

      link_to path, method: :delete, remote: true, class: "dialog-button-secondary", data: data do
        plain " Unsubscribe"
      end
    end
  end
end
