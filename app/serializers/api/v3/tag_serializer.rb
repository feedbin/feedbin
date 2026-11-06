module Api
  module V3
    # Tags are global rows, so the user's subscription_ids are passed in.
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
