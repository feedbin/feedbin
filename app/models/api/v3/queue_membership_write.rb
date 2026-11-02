module Api
  module V3
    # One write to a queue row. Fields a device edits offline (progress, the
    # position, the playlist) each carry {field}_updated_at and the newer
    # value wins field by field; a tie is accepted. The rest are last write
    # wins. Returns the fields written; raises InvalidParameter on a bad body.
    class QueueMembershipWrite
      TRACKED = {"progress_in_seconds" => :progress, "sort_order" => :order, "playlist_id" => :playlist_id}.freeze
      PLAIN = {"duration_in_seconds" => :duration, "skipped_chapters" => :skipped_chapters}.freeze

      def initialize(row, body, pointer: "")
        @row = row
        @body = body
        @pointer = pointer
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
          stamp = @body["#{field}_updated_at"] or raise invalid("#{field}_updated_at", "missing", "#{field}_updated_at is required with #{field}.")
          proposed = Time.iso8601(stamp.to_s) rescue raise(invalid("#{field}_updated_at", "invalid_value", "#{field}_updated_at must be an RFC 3339 timestamp."))
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

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "#{@pointer}/#{field}", code: code)
      end
    end
  end
end
