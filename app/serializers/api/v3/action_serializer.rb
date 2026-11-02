module Api
  module V3
    # The action object. An action that applies to all feeds shows empty
    # feed_ids and tag_ids, whatever the web form left stored beside the
    # all_feeds flag. send_ios_notification pushes the same way as
    # send_push_notification now, so it shows as that.
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
          actions: @action.actions.map { (_1 == "send_ios_notification") ? "send_push_notification" : _1 }.uniq,
          status: @action.status,
          # error_hint revalidates the action against Elasticsearch, so only
          # for the one status that has a hint.
          error_hint: @action.broken? ? @action.error_hint.presence : nil
        }
      end
    end
  end
end
