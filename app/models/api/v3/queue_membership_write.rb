module Api
  module V3
    # One write to a queue row. Fields a device edits offline (progress, the
    # position, the playlist) each carry {field}_updated_at and the newer
    # value wins field by field; a tie is accepted. The rest are last write
    # wins. Returns the fields written; raises InvalidParameter on a bad body.
    class QueueMembershipWrite
      TRACKED = {"progress_in_seconds" => :progress, "sort_order" => :order, "playlist_id" => :playlist_id}.freeze
      PLAIN = {"duration_in_seconds" => :duration, "skipped_chapters" => :skipped_chapters}.freeze
      MAX_ROWS = 1_000

      # Many rows in one transaction, each {id:, ...fields}. A row whose
      # every sent field was stale is skipped; one that sent nothing to
      # change has nothing stale and is applied.
      # => {applied: [ids], skipped: [{id:, reason:}]}
      def self.apply_all(user, bodies)
        unless bodies.is_a?(Array) && bodies.all? { _1.is_a?(Hash) && _1["id"].is_a?(Integer) }
          raise Problems::InvalidParameter.new("entries must be an array of objects with an id.", pointer: "/entries", code: "invalid_value")
        end
        raise Problems::InvalidParameter.new("entries takes at most #{MAX_ROWS} rows.", pointer: "/entries", code: "too_many") if bodies.size > MAX_ROWS

        rows = user.queued_entries.where(entry_id: bodies.map { _1["id"] }).index_by(&:entry_id)
        playlist_ids = user.playlists.pluck(:id).to_set
        applied = []
        skipped = []
        ActiveRecord::Base.transaction do
          bodies.each_with_index do |body, index|
            row = rows[body["id"]]
            next skipped << {id: body["id"], reason: "not_found"} unless row
            written, stale = new(row, body, pointer: "/entries/#{index}", playlist_ids: playlist_ids).apply
            (written.empty? && stale.any?) ? skipped << {id: body["id"], reason: "stale_write"} : applied << body["id"]
          end
        end
        {applied: applied, skipped: skipped}
      end

      # playlist_ids: the user's playlist ids, when a caller writing many rows
      # has them; otherwise looked up.
      def initialize(row, body, pointer: "", playlist_ids: nil)
        @row = row
        @body = body
        @pointer = pointer
        @playlist_ids = playlist_ids
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
          # Client stamps carry whole seconds; the stored time has microseconds.
          # Compare at the client's precision so a same-second write is a tie.
          if proposed < @row.public_send("#{column}_updated_at").floor
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
        @row.update!(attributes) if attributes.any?
        [attributes.keys, stale]
      end

      private

      def playlist_ids
        @playlist_ids ||= Playlist.where(user_id: @row.user_id).pluck(:id).to_set
      end

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "#{@pointer}/#{field}", code: code)
      end
    end
  end
end
