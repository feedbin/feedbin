module Api
  module V3
    # The fbn_v3_ prefix lets secret scanners recognize leaked tokens.
    class TokenGenerator
      PREFIX = "fbn_v3_"

      def self.generate(_options = {})
        "#{PREFIX}#{SecureRandom.alphanumeric(32)}"
      end
    end
  end
end
