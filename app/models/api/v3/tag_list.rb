module Api
  module V3
    # The user's tags with the subscriptions in each, in natural name order.
    # Tags are shared rows; a user "has" a tag through taggings on feeds they
    # subscribe to.
    class TagList
      def initialize(user)
        @user = user
      end

      # => [[tag, [subscription_ids]], ...]
      def each_with_subscription_ids
        subscription_ids_by_feed = @user.subscriptions.pluck(:feed_id, :id).to_h
        by_tag = @user.taggings.pluck(:tag_id, :feed_id).group_by(&:first)
          .transform_values { |rows| rows.filter_map { subscription_ids_by_feed[_1.last] }.uniq.sort }
        Tag.where(id: by_tag.keys).natural_sort_by(&:name).map { [_1, by_tag.fetch(_1.id)] }
      end

      def find(id)
        Tag.where(id: @user.taggings.select(:tag_id)).find(id)
      end

      def serialize(tag)
        _tag, ids = each_with_subscription_ids.find { |t, _| t.id == tag.id } || [tag, []]
        TagSerializer.new(tag, subscription_ids: ids).to_h
      end
    end
  end
end
