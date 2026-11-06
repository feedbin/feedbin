module Api
  module V3
    class ActionSerializer
      def initialize(action)
        @action = action
      end

      def to_h
        {
          object: "action",
          id: @action.id,
          title: @action.title,
          kind: @action.action_type || "standard",
          query: @action.query,
          feed_ids: @action.all_feeds ? [] : @action.feed_ids.reject(&:blank?).map(&:to_i),
          tag_ids: @action.all_feeds ? [] : @action.tag_ids,
          actions: @action.actions.map { (_1 == "send_ios_notification") ? "send_push_notification" : _1 }.uniq,
          status: @action.status,
          # error_hint queries Elasticsearch; only call it when broken.
          error_hint: @action.broken? ? @action.error_hint.presence : nil
        }
      end
    end
  end
end
