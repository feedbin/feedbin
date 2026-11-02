module Api
  module V3
    # The state verbs behind POST /entries/state: mark_read, mark_unread,
    # star and unstar, each with a list of entry ids, applied in one
    # transaction. Ids the user cannot touch are skipped, not fatal. See
    # entries/state in feedbin-api-docs.
    class StateChange
      VERBS = %w[mark_read mark_unread star unstar].freeze
      OPPOSITES = {"mark_unread" => "mark_read", "unstar" => "star"}.freeze
      MAX_IDS = 1_000

      def initialize(user, body)
        @user = user
        @body = body
      end

      # => {applied: {verb => [ids]}, skipped: [{id:, reason:}]}
      def call
        verbs = validate
        permissions = permissions_for(verbs.values.flatten.uniq)

        applied = {}
        skipped = {}
        ActiveRecord::Base.transaction do
          verbs.each do |verb, ids|
            allowed, denied = ids.partition { allowed?(verb, permissions[_1]) }
            denied.each { skipped[_1] ||= permissions[_1].reason }
            apply(verb, allowed.map { permissions[_1].entry })
            applied[verb] = allowed
          end
        end

        {applied: applied, skipped: skipped.map { |id, reason| {id: id, reason: reason} }}
      end

      private

      # => {verb => [ids]}, verbs in VERBS order, ids uniq in request order.
      def validate
        raise invalid("", "missing", "Send at least one verb.") unless @body.is_a?(Hash) && @body.any?

        @body.each_key do |key|
          raise invalid("/#{key}", "unknown", "#{key} is not a verb.") unless VERBS.include?(key)
        end

        verbs = VERBS.filter_map do |verb|
          next unless @body.key?(verb)
          ids = @body[verb]
          unless ids.is_a?(Array) && ids.all? { _1.is_a?(Integer) && _1.positive? }
            raise invalid("/#{verb}", "invalid_value", "#{verb} must be an array of entry ids.")
          end
          raise invalid("/#{verb}", "too_many", "#{verb} takes at most #{MAX_IDS} ids.") if ids.size > MAX_IDS
          [verb, ids.uniq]
        end.to_h

        OPPOSITES.each do |verb, opposite|
          both = verbs.fetch(verb, []) & verbs.fetch(opposite, [])
          raise invalid("/#{verb}", "conflict", "#{both.first} is in both #{opposite} and #{verb}.") if both.any?
        end

        verbs
      end

      def permissions_for(ids)
        EntryAccess.new(@user).permissions_for(ids)
      end

      # mark_read may clear any unread row the user has, as v2 did: an unread
      # row can outlive its subscription (FeedReplacer moves subscriptions),
      # and a client must be able to clear what the unread list shows.
      def allowed?(verb, permission)
        permission.reason.nil? || (verb == "mark_read" && permission.unread)
      end

      def apply(verb, entries)
        return if entries.empty?
        ids = entries.map(&:id)

        case verb
        when "mark_read"
          @user.unread_entries.where(entry_id: ids).delete_all
        when "mark_unread"
          rows = entries.map { UnreadEntry.new_from_owners(@user, _1) }
          UnreadEntry.import(rows, validate: false, on_duplicate_key_ignore: true)
        when "star"
          entries.each { StarredEntry.create_from_owners(@user, _1, "api") }
        when "unstar"
          @user.starred_entries.where(entry_id: ids).destroy_all
        end
      end

      def invalid(pointer, code, detail)
        Problems::InvalidParameter.new(detail, pointer: pointer, code: code)
      end
    end
  end
end
