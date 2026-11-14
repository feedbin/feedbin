module Api
  module V3
    # Conditional GETs are Rails' own: an action answers with
    # `return unless stale?(etag: version)`.
    module Conditional
      extend ActiveSupport::Concern

      included do
        # Part of every ETag: a client cache survives an account switch, and
        # two accounts' lists with the same version must not match.
        etag { @user&.id }
      end

      private

      # A version for a list with nothing cheaper than its own serialization.
      def digest(data)
        Digest::SHA256.hexdigest(JSON.generate(data))[0, 32]
      end
    end
  end
end
