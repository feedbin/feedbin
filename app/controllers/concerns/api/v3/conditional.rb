# List ETags from SyncVersion, and the 304 that goes with them. The check
# runs before the list query, so an unchanged list costs one small read.
module Api
  module V3
    module Conditional
      extend ActiveSupport::Concern

      private

      def versions
        @versions ||= SyncVersion.for(@user)
      end

      # The ETag a list sends: "<list>:<user id>:<version>", quoted and strong.
      # The user id is there because a URL-keyed client cache survives an
      # account switch on the same device, and two accounts at the same
      # version must not match.
      def list_etag(list)
        etag_for(list, versions.fetch(list))
      end

      # For a list whose version is another list's, or a composite.
      def etag_for(name, *parts)
        %("#{name}:#{@user.id}:#{parts.join(":")}")
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
