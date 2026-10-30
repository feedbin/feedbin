module Api
  module V3
    # Access tokens start with fbn_v3_ so secret scanners can recognize a
    # leaked one. 32 alphanumeric characters is about 190 bits.
    class TokenGenerator
      PREFIX = "fbn_v3_"

      def self.generate(_options = {})
        "#{PREFIX}#{SecureRandom.alphanumeric(32)}"
      end
    end
  end
end
