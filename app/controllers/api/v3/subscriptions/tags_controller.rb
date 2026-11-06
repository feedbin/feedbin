module Api
  module V3
    module Subscriptions
      class TagsController < ApiController
        include SubscriptionScoped

        before_action :set_subscription

        def update
          subscription_list.tag(@subscription, strings("tag_names"))
          tags = TagList.new(@user).each_with_subscription_ids.select { |_tag, ids| ids.include?(@subscription.id) }
          render_list(tags.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h })
        end
      end
    end
  end
end
