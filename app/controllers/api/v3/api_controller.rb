module Api
  module V3
    # Every v3 endpoint inherits from here. The spec is in feedbin-api-docs
    # (conventions.md, errors.md, authentication.md).
    class ApiController < ActionController::API
      # Problems first: rescue_from handlers declared later win, so the
      # catch-all StandardError handler has to come before the specific ones.
      include Problems
      include Authentication
      include Pagination
      include Conditional
      include Expansion
      include Params

      # A v3 body is the resource itself, never wrapped in a root key.
      wrap_parameters false

      before_action :validate_content_type
      before_action :forbid_caching

      # Every v3 response is private to its token and must be revalidated
      # with If-None-Match: a URL-keyed cache that served a stored body
      # without asking would show one account's list to another after a
      # switch, and a shared cache must never store one at all.
      def forbid_caching
        # Through the hash: Rails rewrites the header and keeps "private"
        # beside "no-cache" only as an extra.
        response.cache_control.replace(no_cache: true, extras: ["private"])
      end

      # Unmatched v3 paths land here, after authentication, so an unknown
      # route and a missing record look the same.
      def not_found
        status_not_found
      end

      private

      def validate_content_type
        return unless request.post? || request.put? || request.patch?
        return if request.content_length.to_i.zero? && request.raw_post.empty?

        allowed = ["application/json"]
        allowed << "application/merge-patch+json" if request.patch?

        if allowed.include?(request.media_type)
          parse_body
        else
          render_problem :unsupported_media_type, "unsupported_media_type",
            title: "Unsupported media type",
            detail: "Send the body as #{allowed.join(" or ")}."
        end
      end

      # Parse now, so a body that is not JSON is a 400 whether or not the
      # action reads params.
      def parse_body
        request.request_parameters
      end
    end
  end
end
