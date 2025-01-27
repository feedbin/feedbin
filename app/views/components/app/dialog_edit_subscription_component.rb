module App
  class DialogEditSubscriptionComponent < ApplicationComponent
    def view_template
      render App::DialogComponent::Content.new(purpose: :edit_subscription) do |dialog|
        dialog.title do
          "Edit Subscription"
        end
        dialog.body do
          form_with(model: Subscription.new, url: helpers.edit_subscription_path(1), local: false) do |form_builder|
            div class: "mb-2" do
              render Form::TextInputComponent.new do |input|
                input.accessory_leading do
                  span(class: "pl-2") {render FaviconComponent.new(feed: Feed.first)}
                end
                input.input do
                  form_builder.text_field :title, placeholder: "hello", class: "peer text-input"
                end
              end
            end
            # div class: "mb-6" do
            #   render App::FeedStatsComponent.new(feed: @subscription.feed, stats: FeedStat.daily_counts(feed_ids: [@subscription.feed.id]))
            # end
            # render Settings::H2Component.new do
            #   "Tags"
            # end
            # render App::TagFieldsComponent.new(tag_editor: @tag_editor)

          end
        end
        dialog.footer do
          p {"Footer"}
        end
      end
    end
  end
end
