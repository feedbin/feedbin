module Api
  module V3
    module Params
      MAX_IDS = 1_000

      private

      def boolean_param(name)
        return nil unless params.key?(name)
        case params[name]
        when "true" then true
        when "false" then false
        else raise invalid_param(name, "invalid_value", "#{name} must be true or false.")
        end
      end

      def time_param(name)
        return nil unless params.key?(name)
        Timestamp.parse(params[name]) or raise invalid_param(name, "invalid_value", "#{name} must be an RFC 3339 timestamp with a UTC offset.")
      end

      # `of` names the ids in error messages.
      def id_list(name, max: MAX_IDS, of: "ids")
        return nil unless params.key?(name)
        ids = params[name].to_s.split(",").map { Integer(_1.strip, exception: false) }
        raise invalid_param(name, "invalid_value", "#{name} must be comma-separated #{of}.") if ids.empty? || ids.any? { _1.nil? || _1 <= 0 }
        raise invalid_param(name, "too_many", "#{name} takes at most #{max} ids.") if ids.size > max
        ids.uniq
      end

      def invalid_param(name, code, detail)
        Problems::InvalidParameter.new(detail, pointer: name.to_s, code: code)
      end
    end
  end
end
