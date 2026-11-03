# List ETags and the 304 that goes with them. A short list's ETag is a digest
# of the response it would send. An id list's is a fingerprint of its rows,
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

      # The row count and a sum of per-row hashes of columns. Order doesn't
      # matter, so it is a fingerprint of the set: adding or removing any row
      # moves it, and unlike count and newest id, a removal and an insert
      # cannot net out. Postgres answers it from an index on the columns.
      def fingerprint(scope, *columns)
        row = columns.map { scope.connection.quote_column_name(_1) }.join(", ")
        scope.reorder(nil).pick(Arel.sql("count(*)"), Arel.sql("coalesce(sum(hashtext(concat_ws(':', #{row}))), 0)")).join(".")
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
