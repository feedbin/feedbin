module Api
  module V3
    # The action object. An action that applies to all feeds shows empty
    # feed_ids and tag_ids, whatever the web form left stored beside the
    # all_feeds flag.
    class ActionSerializer
      def initialize(action)
        @action = action
      end

      def to_h
        {
          object: "action",
          id: @action.id,
          title: @action.title,
          kind: @action.action_type,
          query: @action.query,
          feed_ids: @action.all_feeds ? [] : @action.feed_ids.reject(&:blank?).map(&:to_i),
          tag_ids: @action.all_feeds ? [] : @action.tag_ids,
          actions: @action.actions,
          status: @action.status,
          # error_hint revalidates the action against Elasticsearch, so only
          # for the one status that has a hint.
          error_hint: @action.broken? ? @action.error_hint.presence : nil
        }
      end
    end
  end
end
