module Dialog
  class EditSubscription < ApplicationComponent
    def initialize(subscriptions:)
      @subscriptions = subscriptions
    end

    def view_template
      @subscriptions.each do |subscription|
        render Item.new(
          subscription: subscription,
          tag_editor: TagEditor.new(helpers.current_user, subscription.feed),
          app: false
        )
      end
    end

    class Item < ApplicationComponent
      def initialize(subscription:, tag_editor:, app:)
        @subscription = subscription
        @tag_editor = tag_editor
        @app = app
      end

      def view_template
        render Dialog::Template::Content.new(dialog_id: helpers.dom_id(@subscription.feed)) do |dialog|
          dialog.title do
            "Edit Subscription"
          end
          dialog.body do
            form_for(@subscription, remote: true, method: :patch, html: {class: 'settings', data: {behavior: "disable_on_submit"}}) do |form_builder|
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
                render App::FeedStatsComponent.new(feed: @subscription.feed, stats: FeedStat.daily_counts(feed_ids: [@subscription.feed.id]))
              end
              render Settings::H2Component.new do
                "Tags"
              end
              render App::TagFieldsComponent.new(tag_editor: @tag_editor)
            end
          end
          dialog.footer do
            div class: "flex items-center" do
              unsubscribe_class = "button-text delete-button text-sm flex items-center gap-2"
              if @app
                link_to subscription_path(@subscription), method: :delete, remote: true, class: unsubscribe_class, data: { confirm: "Are you sure you want to unsubscribe?", feed_id: @subscription.feed.id, behavior: "unsubscribe" } do
                  render SvgComponent.new("icon-delete")
                  plain " Unsubscribe"
                end
              else
                link_to settings_subscription_path(@subscription), method: :delete, class: unsubscribe_class, data: { confirm: "Are you sure you want to unsubscribe?" } do
                  render SvgComponent.new("icon-delete")
                  plain " Unsubscribe"
                end
              end

              button type: "submit", class: "button ml-auto", value: "save" do
                "Save"
              end
            end
          end
        end
      end
    end
  end
end
