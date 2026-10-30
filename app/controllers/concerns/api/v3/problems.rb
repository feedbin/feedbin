# Errors as RFC 9457 problem details, with the spec's two additions: a stable
# `code` clients branch on, and the `request_id` that X-Request-Id carries.
# See errors.md in feedbin-api-docs.
module Api
  module V3
    module Problems
      extend ActiveSupport::Concern

      included do
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
      end

      private

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

      # The type URI that names the error class. It is the same on every host
      # so clients can match it.
      def error_type(code)
        URI::HTTPS.build(host: "api.feedbin.com", path: "/errors/#{code}").to_s
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
