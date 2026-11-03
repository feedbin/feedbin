# List ETags and the 304 that goes with them. A short list's ETag is a digest
# of the response it would send. An id list's is a Fingerprint of its rows,
# computed in the database, so a 304 never loads the ids.
module Api
  module V3
    module Conditional
      extend ActiveSupport::Concern

      private

      # The ETag a list sends: "<name>:<user id>:<parts>", quoted and strong.
      # The user id is there because a URL-keyed client cache survives an
      # account switch on the same device, and two accounts with the same
      # list must not match.
      def etag_for(name, *parts)
        %("#{name}:#{@user.id}:#{parts.join(":")}")
      end

      def digest(data)
        Digest::SHA256.hexdigest(JSON.generate(data))[0, 32]
      end

      # Sets the ETag and answers 304 when the client already has this
      # version. A proxy that compresses the body turns a strong ETag into
      # W/"..." on the way out, so the comparison is weak (RFC 9110 §13.1.2),
      # which Rails' fresh? is not.
      def not_modified?(etag)
        response.set_header("ETag", etag)
        return false unless request.if_none_match_etags.any? { _1 == "*" || _1.delete_prefix("W/") == etag }
        head :not_modified
        true
      end
    end
  end
end
