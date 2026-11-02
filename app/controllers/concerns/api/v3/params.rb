module Api
  module V3
    # Query-string parameters shared across v3: booleans, times (see
    # Timestamp) and id lists.
    module Params
      MAX_IDS = 1_000

      private

      def boolean_param(name)
        return nil unless params.key?(name)
        case params[name]
        when "true" then true
        when "false" then false
        else raise Problems::InvalidParameter.new("#{name} must be true or false.", pointer: name.to_s, code: "invalid_value")
        end
      end

      def time_param(name)
        return nil unless params.key?(name)
        Timestamp.parse(params[name]) or raise Problems::InvalidParameter.new("#{name} must be an RFC 3339 timestamp with a UTC offset.", pointer: name.to_s, code: "invalid_value")
      end

      # Comma-separated ids, at most MAX_IDS.
      def id_list(name)
        return nil unless params.key?(name)
        ids = params[name].to_s.split(",").map { Integer(_1.strip, exception: false) }
        raise Problems::InvalidParameter.new("#{name} must be comma-separated ids.", pointer: name.to_s, code: "invalid_value") if ids.empty? || ids.any?(&:nil?)
        raise Problems::InvalidParameter.new("#{name} takes at most #{MAX_IDS} ids.", pointer: name.to_s, code: "too_many") if ids.size > MAX_IDS
        ids
      end
    end
  end
end
