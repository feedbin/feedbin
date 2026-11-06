module Api
  module V3
    # Assigns, without saving. required: a create (title, kind and scope must be given).
    class ActionWrite
      include BodyFields

      KINDS = %w[standard mute].freeze
      ACTIONS = %w[mark_read star send_push_notification].freeze
      FIXED_ACTIONS = {"mute" => ["mark_read"]}.freeze

      attr_reader :body

      def initialize(user, action, body, required:)
        @user = user
        @action = action
        @body = body
        @required = required
      end

      def apply
        @action.title = required_string("title") if given?("title")
        @action.action_type = one_of("kind", KINDS) if given?("kind")
        @action.query = optional_string("query")&.strip if body.key?("query")
        assign_scope if given?("feed_ids") || body.key?("tag_ids")
        @action.actions = rule_actions if body.key?("actions")
        @action.actions = FIXED_ACTIONS[@action.action_type] if FIXED_ACTIONS.key?(@action.action_type)
        @action
      end

      private

      def given?(field)
        @required || body.key?(field)
      end

      # Empty lists mean every feed. Foreign ids are dropped after this check, so
      # an all-foreign list fails validation instead of matching every feed.
      def assign_scope
        feed_ids = body.key?("feed_ids") ? integer_ids("feed_ids") : stored_feed_ids
        tag_ids = body.key?("tag_ids") ? integer_ids("tag_ids") : stored_tag_ids
        @action.all_feeds = feed_ids.empty? && tag_ids.empty?
        @action.feed_ids = feed_ids & @user.subscriptions.pluck(:feed_id)
        @action.tag_ids = tag_ids & @user.taggings.distinct.pluck(:tag_id)
      end

      def stored_feed_ids
        @action.all_feeds ? [] : @action.feed_ids.reject(&:blank?).map(&:to_i)
      end

      def stored_tag_ids
        @action.all_feeds ? [] : @action.tag_ids
      end

      def rule_actions
        values = body["actions"]
        raise invalid("actions", "invalid_value", "actions must be an array of #{ACTIONS.join(", ")}.") unless values.is_a?(Array) && values.all? { ACTIONS.include?(_1) }
        values.uniq
      end
    end
  end
end
