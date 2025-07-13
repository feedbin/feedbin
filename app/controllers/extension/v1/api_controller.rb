module Extension
  module V1
    class ApiController < ApplicationController
      respond_to :json
      prepend_before_action :cors_headers
      skip_before_action :verify_authenticity_token
      skip_before_action :authorize, only: [:options]

      def options; end

      private

      def authorize
        @current_user ||= begin
          if signed_in?
            current_user
          elsif params[:page_token]
            User.find_by_page_token(params[:page_token])
          else
            User.where("lower(email) = ?", params[:email]).take.try(:authenticate, params[:password])
          end
        end

        unless current_user
          head :unauthorized and return
        end
      end

      def cors_headers
        headers["Access-Control-Allow-Origin"] = "*"
        headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
        headers["Access-Control-Allow-Headers"] = "Origin, Content-Type, Content-Encoding, Accept"
        headers["Access-Control-Max-Age"] = 1.hour.to_i.to_s
      end

      rescue_from ActiveRecord::RecordNotFound do |exception|
        ErrorService.notify(exception)
        status_not_found
      end

      rescue_from ActionController::ParameterMissing do |exception|
        @error = {status: 400, message: "Bad Request", errors: [exception.message]}
        render partial: "api/v2/shared/api_error", status: 400
      end

      rescue_from ArgumentError do |exception|
        @error = {status: 400, message: "Bad Request", errors: [exception.message]}
        render partial: "api/v2/shared/api_error", status: 400
      end

      def status_not_found
        @error = {status: 404, errors: []}
        render partial: "api/v2/shared/api_error", status: :not_found
      end

      def status_forbidden
        @error = {status: 403, errors: []}
        render partial: "api/v2/shared/api_error", status: :forbidden
      end

      def validate_content_type
        unless request.media_type == "application/json"
          @error = {status: 415, message: 'Please use the "Content-Type: application/json; charset=utf-8" header', errors: []}
          render partial: "api/v2/shared/api_error", status: 415
        end
      end
    end
  end
end

