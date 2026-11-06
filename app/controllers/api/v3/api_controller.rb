module Api
  module V3
    class ApiController < ActionController::API
      # Must come first: later rescue_from handlers win over its StandardError catch-all.
      include Problems
      include Authentication
      include Pagination
      include Conditional
      include Expansion
      include Params
      include BodyFields

      wrap_parameters false

      before_action :validate_content_type
      before_action :forbid_caching

      # A URL-keyed client cache would otherwise show one account's data to another
      # after an account switch; shared caches must never store responses.
      def forbid_caching
        # Rails rewrites Cache-Control; "private" survives beside no_cache only as an extra.
        response.cache_control.replace(no_cache: true, extras: ["private"])
      end

      # Runs after authentication, so an unknown route looks like a missing record.
      def not_found
        status_not_found
      end

      private

      # Raw parsed JSON: top-level arrays and nulls arrive as sent, unlike params.
      def body
        request.request_parameters
      end

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

      # Parses eagerly so malformed JSON is a 400 even if the action never reads params.
      def parse_body
        request.request_parameters
      end
    end
  end
end
