module FixFeeds
  class IndexView < ApplicationView

    def initialize(user:, subscriptions:)
      @user = user
      @subscriptions = subscriptions
    end

    def template
      render Settings::H1Component.new do
        "Fix Feeds"
      end

      p(class: "text-500 mb-8") do
        if @subscriptions.present?
          "Feedbin is no longer able to download these feeds from their original source. However, there may be working alternatives available. You can review the options below."
        else
          "If Feedbin finds working alternatives to feeds that have stopped updating, they will show up here."
        end
      end

      if @subscriptions.present?
        render StatusComponent.new(count: @subscriptions.count, replace_path: helpers.replace_all_fix_feeds_path)
      end

      @subscriptions.each do |subscription|
        render App::ExpandableContainerComponent.new(open: true) do |expandable|
          expandable.content do
            div class: "border rounded-lg mb-4 p-4" do
              render SuggestionComponent.new(replaceable: subscription, source: subscription.feed, redirect: helpers.fix_feeds_url, include_ignore: true)
            end
          end
        end
      end
    end
  end
end
