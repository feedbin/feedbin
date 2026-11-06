module Api
  module V3
    # RFC 3339 with a required UTC offset; without one Ruby uses the server's zone.
    module Timestamp
      FORMAT = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?(Z|[+-]\d\d:\d\d)\z/

      # nil when the value is not such a time.
      def self.parse(value)
        string = value.to_s
        Time.iso8601(string) if FORMAT.match?(string)
      rescue ArgumentError
        nil
      end
    end
  end
end
