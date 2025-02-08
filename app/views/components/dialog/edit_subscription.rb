module Dialog
  class EditSubscription < ApplicationComponent
    def initialize(subscriptions:, app: true)
      @subscriptions = subscriptions
      @app = app
    end

    def view_template
      stats = FeedStat.daily_counts(feed_ids: @subscriptions.map(&:feed_id))
      taggings = TagEditor.taggings(helpers.current_user)
      @subscriptions.each do |subscription|
        tag_editor = TagEditor.new(taggings: taggings, user: helpers.current_user, feed: subscription.feed)
        render Item.new(
          subscription: subscription,
          tag_editor: tag_editor,
          stats: stats,
          app: @app # used to distinguish between the edit modal in the main app vs settings
        )
      end
    end

    class Item < ApplicationComponent
      def initialize(subscription:, tag_editor:, stats:, app:)
        @subscription = subscription
        @tag_editor = tag_editor
        @stats = stats
        @app = app
      end

      def view_template
        render Dialog::Template::Content.new(dialog_id: helpers.dom_id(@subscription.feed)) do |dialog|
          dialog.title do
            "Edit Subscription"
          end
          dialog.body do
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
              render Settings::H2Component.new do
                "Tags"
              end
              render App::TagFieldsComponent.new(tag_editor: @tag_editor)
            end
          end
          dialog.footer do
            div class: "flex items-center" do
              unsubscribe_link

              button type: "submit", class: "button ml-auto", value: "save", form: helpers.dom_id(@subscription, :edit) do
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

        link_to path, method: :delete, remote: true, class: "!text-600 button-text text-sm flex items-center gap-2", data: data do
          render SvgComponent.new("icon-delete", class: "fill-600")
          plain " Unsubscribe"
        end
      end
    end
  end
end
