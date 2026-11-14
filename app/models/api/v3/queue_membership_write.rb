module Api
  module V3
    class QueueMembershipWrite
      TRACKED = {"progress_in_seconds" => :progress, "sort_order" => :order, "playlist_id" => :playlist_id}.freeze
      PLAIN = {"duration_in_seconds" => :duration, "skipped_chapters" => :skipped_chapters}.freeze
      MAX_ROWS = 1_000

      # => {applied: [ids], skipped: [{id:, reason:}]}
      def self.apply_all(user, bodies)
        unless bodies.is_a?(Array) && bodies.all? { _1.is_a?(Hash) && _1["id"].is_a?(Integer) }
          raise Problems::InvalidParameter.new("entries must be an array of objects with an id.", pointer: "/entries", code: "invalid_value")
        end
        raise Problems::InvalidParameter.new("entries takes at most #{MAX_ROWS} rows.", pointer: "/entries", code: "too_many") if bodies.size > MAX_ROWS

        rows = user.queued_entries.where(entry_id: bodies.map { _1["id"] }).index_by(&:entry_id)
        playlist_ids = user.playlists.pluck(:id).to_set
        stamps = stamps_for(rows.values)
        applied = []
        skipped = []
        ActiveRecord::Base.transaction do
          bodies.each_with_index do |body, index|
            row = rows[body["id"]]
            next skipped << {id: body["id"], reason: "not_found"} unless row
            written, stale = new(row, body, pointer: "/entries/#{index}", playlist_ids: playlist_ids, stamps: stamps).apply
            (written.empty? && stale.any?) ? skipped << {id: body["id"], reason: "stale_write"} : applied << body["id"]
          end
        end
        {applied: applied, skipped: skipped}
      end

      # {[queued entry id, column] => when it was last written}, in one read
      # for a bulk write. A column never written has no entry.
      def self.stamps_for(rows)
        AttributeChange.where(trackable_type: QueuedEntry.polymorphic_name, trackable_id: rows.map(&:id), name: TRACKED.values)
          .pluck(:trackable_id, :name, :updated_at)
          .to_h { |id, name, time| [[id, name], time] }
      end

      # playlist_ids, stamps: optional preloads for bulk writes.
      def initialize(row, body, pointer: "", playlist_ids: nil, stamps: nil)
        @row = row
        @body = body
        @pointer = pointer
        @playlist_ids = playlist_ids
        @stamps = stamps
      end

      # => [written attribute names, stale attribute names]
      def apply
        attributes = {}
        stale = []
        TRACKED.each do |field, column|
          next unless @body.key?(field)
          value = @body[field]
          raise invalid(field, "invalid_value", "#{field} must be an integer.") unless value.nil? || value.is_a?(Integer)
          raise invalid(field, "invalid_value", "#{field} cannot be null.") if value.nil? && field != "playlist_id"
          raise invalid(field, "invalid_value", "playlist_id must be one of the user's playlists.") if field == "playlist_id" && value && !playlist_ids.include?(value)
          stamp = @body["#{field}_updated_at"] or raise invalid("#{field}_updated_at", "missing", "#{field}_updated_at is required with #{field}.")
          proposed = Timestamp.parse(stamp) or raise invalid("#{field}_updated_at", "invalid_value", "#{field}_updated_at must be an RFC 3339 timestamp with a UTC offset.")
          # Client stamps carry whole seconds; compare at that precision.
          if proposed < written_at(column).floor
            stale << field
          else
            attributes[column] = value
          end
        end
        PLAIN.each do |field, column|
          next unless @body.key?(field)
          value = @body[field]
          valid = (column == :skipped_chapters) ? value.is_a?(Array) && value.all? { _1.is_a?(Integer) } : value.is_a?(Integer)
          raise invalid(field, "invalid_value", "#{field} is invalid.") unless valid
          attributes[column] = value
        end
        save(attributes) if attributes.any?
        [attributes.keys, stale]
      end

      private

      def written_at(column)
        return @row.public_send("#{column}_updated_at") unless @stamps
        @stamps[[@row.id, column.to_s]] || @row.updated_at
      end

      # Keeps the preloaded stamps current, for a row sent twice in one write.
      def save(attributes)
        @row.assign_attributes(attributes)
        changed = TRACKED.values.select { @row.will_save_change_to_attribute?(it) }
        @row.save!
        changed.each { @stamps[[@row.id, it.to_s]] = Time.current } if @stamps
      end

      def playlist_ids
        @playlist_ids ||= Playlist.where(user_id: @row.user_id).pluck(:id).to_set
      end

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "#{@pointer}/#{field}", code: code)
      end
    end
  end
end
