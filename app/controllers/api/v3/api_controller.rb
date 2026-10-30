module Api
  module V3
    # Every v3 endpoint inherits from here. It authenticates the request,
    # checks that the account may use v3, and renders the shared shapes: the
    # list envelope and RFC 9457 problem details. The spec is in
    # feedbin-api-docs (conventions.md, errors.md, authentication.md).
    class ApiController < ActionController::API
      class InvalidLimit < StandardError; end

      DEFAULT_LIMIT = 100
      MAX_LIMIT = 1_000
      LAST_USED_RESOLUTION = 5.minutes

      before_action :authenticate
      before_action :authorize_account
      before_action :validate_content_type

      rescue_from StandardError do |exception|
        raise exception if Rails.application.config.consider_all_requests_local
        ErrorService.notify(exception)
        render_problem :internal_server_error, "server_error",
          title: "Server error",
          detail: "Something broke on our side. The request is safe to retry."
      end

      rescue_from ActiveRecord::RecordNotFound do
        status_not_found
      end

      rescue_from ActionDispatch::Http::Parameters::ParseError do
        render_problem :bad_request, "bad_request",
          title: "Bad request",
          detail: "The request body is not valid JSON."
      end

      rescue_from ActionController::ParameterMissing do |exception|
        status_validation_failed([{pointer: "/#{exception.param}", code: "missing", detail: "#{exception.param} is required."}])
      end

      rescue_from InvalidLimit do |exception|
        status_validation_failed([{pointer: "limit", code: "out_of_range", detail: exception.message}])
      end

      rescue_from Cursor::Invalid do
        render_problem :bad_request, "cursor_invalid",
          title: "Invalid cursor",
          detail: "The cursor could not be decoded. Restart from the first page."
      end

      # Unmatched v3 paths land here, after authentication, so an unknown
      # route and a missing record look the same.
      def not_found
        status_not_found
      end

      private

      # Bearer tokens only. v3 does not take the account password, not even
      # as HTTP Basic auth.
      def authenticate
        authenticate_with_token if bearer_authorization?
        status_unauthorized unless @user
      end

      def bearer_authorization?
        request.authorization.to_s.match?(/\ABearer\s/i)
      end

      def authenticate_with_token
        token = Doorkeeper::OAuth::Token.authenticate(request, :from_bearer_authorization)
        return unless token&.accessible?

        @user = User.includes(:plan).find_by(id: token.resource_owner_id)
        token.update_column(:last_used_at, Time.now) unless token.last_used_at&.after?(LAST_USED_RESOLUTION.ago)
      end

      def authorize_account
        ErrorService.context(user_id: @user.id)

        if !@user.api_v3_enabled? || @user.suspended || @user.plan.restricted?
          render_problem :forbidden, "restricted",
            title: "Restricted",
            detail: "This account does not have access to the API."
        end
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

      # Parse now, so a body that is not JSON is a 400 whether or not the
      # action reads params.
      def parse_body
        request.request_parameters
      end

      # The list envelope: every list response has this shape.
      def render_list(data, page: nil, meta: {})
        body = {object: "list", data: data}
        body[:page] = page if page
        body[:meta] = {as_of: as_of}.merge(meta)
        render json: body
      end

      # The page object for a paginated list. next_cursor is nil on the last
      # page, and next_url follows it.
      def page_object(limit:, next_cursor:)
        {
          limit: limit,
          next_cursor: next_cursor,
          next_url: next_cursor && next_page_url(next_cursor)
        }
      end

      # This request with cursor replaced, ready for the client to follow.
      def next_page_url(cursor)
        uri = URI(request.url)
        uri.query = request.query_parameters.merge("cursor" => cursor).to_query
        uri.to_s
      end

      # Query parameter errors point at the parameter's name, not a JSON
      # Pointer, as errors.md describes.
      def page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
        return default unless params.key?(:limit)
        limit = Integer(params[:limit], exception: false)
        raise InvalidLimit, "limit must be an integer from 1 to #{max}." unless limit&.between?(1, max)
        limit
      end

      def cursor_fields
        params[:cursor].present? ? Cursor.decode(params[:cursor]) : nil
      end

      def as_of
        @as_of ||= Time.now.utc.iso8601
      end

      def render_problem(status, code, title:, detail:, errors: nil)
        body = {
          type: error_type(code),
          title: title,
          status: Rack::Utils.status_code(status),
          code: code,
          detail: detail,
          request_id: request.request_id
        }
        body[:errors] = errors if errors
        render json: body, status: status, content_type: "application/problem+json"
      end

      # The RFC 9457 type URI that names the error class. It is the same on
      # every host so clients can match it.
      def error_type(code)
        URI::HTTPS.build(host: "api.feedbin.com", path: "/errors/#{code}").to_s
      end

      def status_unauthorized
        challenge = %(Bearer realm="Feedbin")
        challenge += %(, error="invalid_token") if bearer_authorization?
        response.headers["WWW-Authenticate"] = challenge
        render_problem :unauthorized, "unauthorized",
          title: "Unauthorized",
          detail: "The access token is missing or has been revoked."
      end

      def status_not_found
        render_problem :not_found, "not_found",
          title: "Not found",
          detail: "The resource does not exist."
      end

      def status_validation_failed(errors)
        render_problem :unprocessable_content, "validation_failed",
          title: "Validation failed",
          detail: "The request was understood but #{errors.one? ? "a value is" : "#{errors.size} values are"} invalid.",
          errors: errors
      end
    end
  end
end
