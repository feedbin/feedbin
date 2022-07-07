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

        def remove_stale_updates(record, update_params, original_params)
          attributes = update_params.keys
          attributes.each do |attribute|
            updated_attribute = "#{attribute}_updated_at".to_sym
            proposed_updated_at = original_params.fetch(updated_attribute)
            proposed_updated_at = Time.parse(proposed_updated_at)

            next unless record.respond_to?(updated_attribute)

            updated_at = record.public_send(updated_attribute)

            if proposed_updated_at < updated_at
              update_params.delete(attribute)
            end
          end
          update_params
        end

        def updated_at(attribute)
          param_name = "#{attribute}_updated_at"
          updated_at = params.fetch(param_name)
          Time.parse(updated_at)
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
end
