module Api
  module V3
    class StateChange
      VERBS = %w[mark_read mark_unread star unstar clear_updated].freeze
      SCOPED_VERBS = %w[mark_read clear_updated].freeze
      OPPOSITES = {"mark_unread" => "mark_read", "unstar" => "star"}.freeze
      SCOPE_KEYS = %w[feed_ids tag_ids collection published_before received_before].freeze
      SCOPE_COLLECTIONS = %w[unread all starred updated recently_read pages].freeze
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
              applied[verb] = {count: target.delete_all}
              next
            end
            allowed, denied = target.partition { allowed?(verb, permissions[_1], updated.include?(_1)) }
            denied.each { skipped[_1] ||= permissions[_1].reason }
            apply(verb, allowed, allowed.filter_map { permissions[_1].entry })
            applied[verb] = allowed
          end
        end

        {applied: applied, skipped: skipped.map { |id, reason| {id: id, reason: reason} }}
      end

      # Keys combine with AND; no keys selects every row.
      class Scope
        SLICE = 10_000

        def initialize(user, verb, scope)
          @user = user
          @verb = verb
          @relation = (verb == "mark_read") ? user.unread_entries : user.updated_entries
          # collection must be last: a saved search walks only the rows the other keys leave.
          scope.sort_by { |key, _| (key == "collection") ? 1 : 0 }.each { |key, value| narrow(key, value) }
        end

        def delete_all
          return @relation.delete_all unless @search_ids
          @search_ids.each_slice(SLICE).sum { @relation.where(entry_id: _1).delete_all }
        end

        private

        def narrow(key, value)
          case key
          when "feed_ids" then @relation = @relation.where(feed_id: id_list(key, value))
          when "tag_ids" then @relation = @relation.where(feed_id: @user.taggings.where(tag_id: id_list(key, value)).select(:feed_id))
          when "collection" then narrow_to_collection(value)
          when "published_before" then @relation = @relation.where(published: ...bound(key, value))
          when "received_before" then @relation = @relation.where(((@verb == "mark_read") ? :entry_created_at : :updated_at) => ...bound(key, value))
          else raise invalid(key, "unknown", "#{key} is not a scope key. Use #{SCOPE_KEYS.join(", ")}.")
          end
        end

        def narrow_to_collection(id)
          collection = Collection.find(@user, id) if id.is_a?(String) && (SCOPE_COLLECTIONS.include?(id) || id.start_with?("search_"))
          raise invalid("collection", "invalid_value", "collection must be #{SCOPE_COLLECTIONS.join(", ")}, or a saved search's collection id.") unless collection
          return if collection.timeline? || (@verb == "mark_read" && id == "unread") || (@verb == "clear_updated" && id == "updated")
          if collection.search?
            @search_ids = search_matches(collection)
          elsif collection.pages?
            @relation = @relation.where(entry_id: collection.pages.select(:id))
          else
            @relation = @relation.where(entry_id: collection.rows.reorder(nil).select(:entry_id))
          end
        end

        # Every match, not just the 50 in the id list. Filtering to the user's rows
        # bounds the walk however broad the query.
        def search_matches(collection)
          query = Entry.build_query(user: @user, query: collection.query)
          index = Search.index_name(Entry.table_name)
          case Search.client { _1.validate(index, query: {query: query[:query]}) }
          when false then raise EntrySearch::QueryInvalid, "The saved search's query could not be parsed."
          when nil then raise Search::Connection::ResponseError, "Elasticsearch did not validate the saved search's query."
          end
          candidates = @relation.pluck(:entry_id)
          return [] if candidates.empty?
          bool = query[:query][:bool]
          bool[:filter] = [bool[:filter], {ids: {values: candidates}}]
          Search.client { _1.all_matches(index, query: query) }
        end

        def id_list(key, value)
          raise invalid(key, "invalid_value", "#{key} must be an array of ids.") unless value.is_a?(Array) && value.all? { _1.is_a?(Integer) && _1.positive? }
          raise invalid(key, "too_many", "#{key} takes at most #{MAX_IDS} ids.") if value.size > MAX_IDS
          value
        end

        # Exclusive end of the named instant at the precision sent: times go out in
        # whole seconds but rows store microseconds, so a copied bound must include its entry.
        def bound(key, value)
          time = Timestamp.parse(value) or raise invalid(key, "invalid_value", "#{key} must be an RFC 3339 timestamp with a UTC offset.")
          time + Rational(1, 10**value.to_s[/\.(\d+)/, 1].to_s.length)
        end

        def invalid(key, code, detail)
          Problems::InvalidParameter.new(detail, pointer: "/#{@verb}/#{key}", code: code)
        end
      end

      private

      # => {verb => [ids] or Scope}, verbs in VERBS order.
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

        OPPOSITES.each do |verb, opposite|
          both = Array(verbs[verb]) & Array(verbs[opposite])
          raise invalid("/#{verb}", "conflict", "#{both.first} is in both #{opposite} and #{verb}.") if both.any?
        end

        verbs
      end

      def permissions_for(ids)
        EntryAccess.new(@user).permissions_for(ids)
      end

      # Unread and Updated rows can outlive their subscription (FeedReplacer), so
      # they're clearable regardless of access.
      def allowed?(verb, permission, updated)
        permission.reason.nil? || (verb == "mark_read" && permission.unread) || (verb == "clear_updated" && updated)
      end

      # Updated rows have no foreign key, so clear_updated can name a deleted entry.
      def apply(verb, ids, entries)
        return if ids.empty?

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
