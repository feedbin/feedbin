module Api
  module V3
    # An opaque pagination cursor: a position in the sort, encoded as hex JSON
    # so it needs no escaping in a URL. Clients pass it back unchanged.
    class Cursor
      class Invalid < StandardError; end

      def self.encode(fields)
        JSON.generate(fields).unpack1("H*")
      end

      def self.decode(cursor)
        raise Invalid unless cursor.is_a?(String) && cursor.match?(/\A(?:[0-9a-f]{2})+\z/)
        fields = JSON.parse([cursor].pack("H*"))
        raise Invalid unless fields.is_a?(Hash)
        fields
      rescue JSON::ParserError, EncodingError
        raise Invalid
      end
    end
  end
end
