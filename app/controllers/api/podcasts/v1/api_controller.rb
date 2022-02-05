module Api
  module Podcasts
    module V1
      class ApiController < ApplicationController
        respond_to :json
        skip_before_action :verify_authenticity_token

        private

        def hex_decode(string)
          string.scan(/../).map { |x| x.hex.chr }.join
        end

        rescue_from ActiveRecord::RecordNotFound do |exception|
          Honeybadger.notify(exception)
          status_not_found
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
end
