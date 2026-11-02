module Api
  module V3
    # The state verbs behind POST /entries/state: mark_read, mark_unread,
    # star, unstar and clear_updated, each with a list of entry ids, applied
    # in one transaction. Ids the user cannot touch are skipped, not fatal.
    # mark_read and clear_updated also take a scope, which sweeps the user's
    # own rows in one statement and reports a count. See entries/state in
    # feedbin-api-docs.
    class StateChange
      VERBS = %w[mark_read mark_unread star unstar clear_updated].freeze
      SCOPED_VERBS = %w[mark_read clear_updated].freeze
      OPPOSITES = {"mark_unread" => "mark_read", "unstar" => "star"}.freeze
      SCOPE_KEYS = %w[feed_ids tag_ids collection published_before received_before].freeze
      # The collections a scope can name: those whose entries take state
      # writes, plus Recently Read and saved searches. Not Airshow or Recently
      # Played.
      SCOPE_COLLECTIONS = %w[unread all starred updated recently_read].freeze
      MAX_IDS = 1_000

      def initialize(user, body)
        @user = user
        @body = body
      end

      # => {applied: {verb => [ids] or {count:}}, skipped: [{id:, reason:}]}
      def call
        verbs = validate
        ids = verbs.values.select { _1.is_a?(Array) }.flatten.uniq
        permissions = permissions_for(ids)
        updated = verbs.key?("clear_updated") ? @user.updated_entries.where(entry_id: ids).pluck(:entry_id).to_set : Set.new

        applied = {}
        skipped = {}
        ActiveRecord::Base.transaction do
          verbs.each do |verb, target|
            if target.is_a?(Scope)
              applied[verb] = {count: target.relation.delete_all}
              next
            end
            allowed, denied = target.partition { allowed?(verb, permissions[_1], updated.include?(_1)) }
            denied.each { skipped[_1] ||= permissions[_1].reason }
            apply(verb, allowed.map { permissions[_1].entry })
            applied[verb] = allowed
          end
        end

        {applied: applied, skipped: skipped.map { |id, reason| {id: id, reason: reason} }}
      end

      # The user's rows in one state table that a scope object selects. Keys
      # combine with AND; no keys selects every row.
      class Scope
        attr_reader :relation

        def initialize(user, verb, scope)
          @user = user
          @verb = verb
          @relation = (verb == "mark_read") ? user.unread_entries : user.updated_entries
          scope.each { |key, value| narrow(key, value) }
        end

        private

        def narrow(key, value)
          case key
          when "feed_ids" then @relation = @relation.where(feed_id: id_list(key, value))
          when "tag_ids" then @relation = @relation.where(feed_id: @user.taggings.where(tag_id: id_list(key, value)).select(:feed_id))
          when "collection" then narrow_to_collection(value)
          when "published_before" then @relation = @relation.where(published: ...bound(key, value))
          # When the row's entry reached the list: arrival for unread, the
          # edit for Updated, the keys those collections page on.
          when "received_before" then @relation = @relation.where(((@verb == "mark_read") ? :entry_created_at : :updated_at) => ...bound(key, value))
          else raise invalid(key, "unknown", "#{key} is not a scope key. Use #{SCOPE_KEYS.join(", ")}.")
          end
        end

        def narrow_to_collection(id)
          collection = Collection.find(@user, id) if id.is_a?(String) && (SCOPE_COLLECTIONS.include?(id) || id.start_with?("search_"))
          raise invalid("collection", "invalid_value", "collection must be #{SCOPE_COLLECTIONS.join(", ")}, or a saved search's collection id.") unless collection
          # A table sweeps itself whole; the timeline is every row.
          return if collection.timeline? || (@verb == "mark_read" && id == "unread") || (@verb == "clear_updated" && id == "updated")
          @relation = @relation.where(entry_id: collection.search? ? search_matches(collection) : collection.rows.reorder(nil).select(:entry_id))
        end

        # Every match, not the 50 a saved search's id list carries. The id
        # list is fixed before the delete, so an entry that arrives during
        # the sweep is not in it.
        def search_matches(collection)
          query = Entry.build_query(user: @user, query: collection.query)
          Search.client { _1.all_matches(Search.index_name(Entry.table_name), query: query) }
        end

        def id_list(key, value)
          raise invalid(key, "invalid_value", "#{key} must be an array of ids.") unless value.is_a?(Array) && value.all? { _1.is_a?(Integer) && _1.positive? }
          raise invalid(key, "too_many", "#{key} takes at most #{MAX_IDS} ids.") if value.size > MAX_IDS
          value
        end

        # The exclusive end of the instant the client named. Entry times go out
        # in whole seconds while rows store microseconds, so a bound copied
        # from an entry's received_at must still include that entry: the
        # bound covers its whole last unit at the precision sent.
        def bound(key, value)
          time = Time.iso8601(value.to_s)
          time + Rational(1, 10**value.to_s[/\.(\d+)/, 1].to_s.length)
        rescue ArgumentError
          raise invalid(key, "invalid_value", "#{key} must be an RFC 3339 timestamp.")
        end

        def invalid(key, code, detail)
          Problems::InvalidParameter.new(detail, pointer: "/#{@verb}/#{key}", code: code)
        end
      end

      private

      # => {verb => [ids] or Scope}, verbs in VERBS order, ids uniq in
      # request order.
      def validate
        raise invalid("", "missing", "Send at least one verb.") unless @body.is_a?(Hash) && @body.any?

        @body.each_key do |key|
          raise invalid("/#{key}", "unknown", "#{key} is not a verb.") unless VERBS.include?(key)
        end

        verbs = VERBS.filter_map do |verb|
          next unless @body.key?(verb)
          value = @body[verb]
          next [verb, Scope.new(@user, verb, value)] if value.is_a?(Hash) && SCOPED_VERBS.include?(verb)
          unless value.is_a?(Array) && value.all? { _1.is_a?(Integer) && _1.positive? }
            detail = SCOPED_VERBS.include?(verb) ? "#{verb} must be an array of entry ids or a scope." : "#{verb} must be an array of entry ids."
            raise invalid("/#{verb}", "invalid_value", detail)
          end
          raise invalid("/#{verb}", "too_many", "#{verb} takes at most #{MAX_IDS} ids.") if value.size > MAX_IDS
          [verb, value.uniq]
        end.to_h

        # A mark_read scope beside mark_unread ids is not a conflict: verbs
        # apply in order, so those ids end up unread.
        OPPOSITES.each do |verb, opposite|
          both = Array(verbs[verb]) & Array(verbs[opposite])
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
      # clear_updated may likewise clear any Updated row the user has.
      def allowed?(verb, permission, updated)
        permission.reason.nil? || (verb == "mark_read" && permission.unread) || (verb == "clear_updated" && updated)
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
        when "clear_updated"
          @user.updated_entries.where(entry_id: ids).delete_all
        end
      end

      def invalid(pointer, code, detail)
        Problems::InvalidParameter.new(detail, pointer: pointer, code: code)
      end
    end
  end
end
