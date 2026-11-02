module Api
  module V3
    # One write to a queue row. Fields a device edits offline (progress, the
    # position, the playlist) each carry {field}_updated_at and the newer
    # value wins field by field; a tie is accepted. The rest are last write
    # wins. Returns the fields written; raises InvalidParameter on a bad body.
    class QueueMembershipWrite
      TRACKED = {"progress_in_seconds" => :progress, "sort_order" => :order, "playlist_id" => :playlist_id}.freeze
      PLAIN = {"duration_in_seconds" => :duration, "skipped_chapters" => :skipped_chapters}.freeze

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
