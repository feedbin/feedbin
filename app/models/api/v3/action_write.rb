module Api
  module V3
    # Assigns an action rule from a request body, without saving. required:
    # a create, where title, kind and the scope must be given. A mute always
    # marks read, so its actions are set here rather than taken from the
    # body. The notifier belonged to the retired Feedbin Notifier: v3 neither
    # shows nor accepts one.
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

      # Both lists empty as sent means every feed. Ids the user cannot use
      # are dropped afterwards, so a list of only foreign ids fails
      # validation instead of widening the rule to every feed.
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
