module Api
  module V3
    # The tag object. Tags are global rows keyed by name; what belongs to the
    # user is the set of tagged subscriptions, so subscription_ids is passed in.
    # tags.name is nullable; a nameless tag is "".
    class TagSerializer
      def initialize(tag, subscription_ids:)
        @tag = tag
        @subscription_ids = subscription_ids
      end

      def to_h
        {object: "tag", id: @tag.id, name: @tag.name.to_s, subscription_ids: @subscription_ids}
      end
    end
  end
end
