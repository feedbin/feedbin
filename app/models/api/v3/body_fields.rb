module Api
  module V3
    # Typed readers for a JSON request body. Each takes the field's name and
    # by default reads it from #body; a bad value raises InvalidParameter with
    # a JSON pointer to the field, under @pointer when the body sits inside a
    # larger one. A nested field is named by its path ("preferences/muted"),
    # and the message names only its last segment.
    module BodyFields
      private

      def required_string(field, value = body[field])
        raise invalid(field, "missing", "#{label(field)} is required.") unless value.is_a?(String) && value.strip.present?
        value.strip
      end

      def optional_string(field, value = body[field], detail: "#{label(field)} must be a string.")
        raise invalid(field, "invalid_value", detail) unless value.nil? || value.is_a?(String)
        value
      end

      def boolean(field, value = body[field])
        raise invalid(field, "invalid_value", "#{label(field)} must be true or false.") unless [true, false].include?(value)
        value
      end

      def object(field, value = body[field])
        raise invalid(field, "invalid_value", "#{label(field)} must be an object.") unless value.is_a?(Hash)
        value
      end

      # choices is a list, or a hash from wire values to stored ones.
      def one_of(field, choices, value = body[field], detail: "#{label(field)} must be one of #{choices.to_a.map { Array(_1).first }.join(", ")}.")
        raise invalid(field, "invalid_value", detail) unless choices.include?(value)
        choices.is_a?(Hash) ? choices.fetch(value) : value
      end

      def integer_ids(field, value = body[field], detail: "#{label(field)} must be an array of ids.")
        raise invalid(field, "invalid_value", detail) unless value.is_a?(Array) && value.all? { _1.is_a?(Integer) }
        value.uniq
      end

      def strings(field, value = body[field])
        raise invalid(field, "invalid_value", "#{label(field)} must be an array of strings.") unless value.is_a?(Array) && value.all? { _1.is_a?(String) }
        value
      end

      # The {field}_updated_at that must come with an offline-edited field.
      def updated_at(field)
        stamp_field = "#{field}_updated_at"
        stamp = body[stamp_field] or raise invalid(stamp_field, "missing", "#{stamp_field} is required with #{field}.")
        Timestamp.parse(stamp) or raise invalid(stamp_field, "invalid_value", "#{stamp_field} must be an RFC 3339 timestamp with a UTC offset.")
      end

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "#{@pointer}/#{field}", code: code)
      end

      def label(field)
        field.to_s.split("/").last
      end
    end
  end
end
