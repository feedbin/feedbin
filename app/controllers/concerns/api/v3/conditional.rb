module Api
  module V3
    module Conditional
      extend ActiveSupport::Concern

      private

      # Includes the user id: a client cache survives an account switch, and two
      # accounts' identical lists must not match.
      def etag_for(name, *parts)
        %("#{name}:#{@user.id}:#{parts.join(":")}")
      end

      def digest(data)
        Digest::SHA256.hexdigest(JSON.generate(data))[0, 32]
      end

      # Weak comparison, unlike Rails' fresh?: compressing proxies turn a strong
      # ETag into W/"...".
      def not_modified?(etag)
        response.set_header("ETag", etag)
        return false unless request.if_none_match_etags.any? { _1 == "*" || _1.delete_prefix("W/") == etag }
        head :not_modified
        true
      end
    end
  end
end
