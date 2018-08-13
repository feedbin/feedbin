module Api
  module V2
    class ApiController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :valid_user, if: :signed_in?

      def entries_response(path_helper)
        if params.has_key?(:read)
          @entries = @entries.include_unread_entries(@user.id)

          if "true" == params[:read]
            @entries = @entries.read_new
          elsif "false" == params[:read]
            @entries = @entries.unread_new
          end
        end

        if params.has_key?(:starred) && "false" == params[:starred]
          @entries = @entries.include_starred_entries(@user.id)
          @entries = @entries.unstarred_new
        end

        if params.has_key?(:since)
          time = Time.iso8601(params[:since])
          @entries = @entries.where("entries.created_at > :time", {time: time})
        end

        if @starred_entries
          page_query = @starred_entries
        else
          page_query = @entries
        end

        if page_query.out_of_bounds?
          status_not_found
        elsif !@entries.present?
          @entries = []
        else
          links_header(page_query, path_helper, params[:feed_id])
          fresh_when(etag: @entries)
        end
      end

      rescue_from ArgumentError do |exception|
        @error = {status: 400, message: "Bad Request", errors: []}
        if "invalid date" == exception.message
          @error[:errors] << {since: "invalid date format"}
        end
        render partial: "api/v2/shared/api_error", status: 400
        Honeybadger.notify(exception)
      end

      rescue_from ActiveRecord::RecordNotFound do |exception|
        @error = {status: 404, message: "Not Found", errors: []}
        render partial: "api/v2/shared/api_error", status: 404
        Honeybadger.notify(exception)
      end

      rescue_from MultiJson::DecodeError do |exception|
        @error = {status: 400, message: "Problem parsing JSON", errors: []}
        render partial: "api/v2/shared/api_error", status: 400
        Honeybadger.notify(exception)
      end

      private

      def status_not_found
        @error = {status: 404, errors: []}
        render partial: "api/v2/shared/api_error", status: :not_found
      end

      def status_forbidden
        @error = {status: 403, errors: []}
        render partial: "api/v2/shared/api_error", status: :forbidden
      end

      def status_bad_request(errors = [])
        @error = {status: 400, errors: errors}
        render partial: "api/v2/shared/api_error", status: :bad_request
      end

      def validate_content_type
        unless request.content_type == "application/json"
          @error = {status: 415, message: 'Please use the "Content-Type: application/json; charset=utf-8" header', errors: []}
          render partial: "api/v2/shared/api_error", status: 415
        end
      end

      def needs(*keys)
        needs_nested(params, *keys)
      end

      def needs_nested(parameters, *keys)
        missing = keys.reject { |key| parameters.has_key? key }
        if missing.any?
          @error = {status: 400, errors: []}
          missing.map { |key| @error[:errors] << {key => "Missing parameter: #{key}"} }
          render partial: "api/v2/shared/api_error", status: 400 and return
        end
      end

      def links_header(collection, url_helper, resource = nil)
        links = []
        link_template = '<%s>; rel="%s"'

        options = {format: :json}
        options[:since] = Time.iso8601(params[:since]).iso8601(6) if params[:since]
        options[:read] = params[:read] if params[:read]
        options[:starred] = params[:starred] if params[:starred]
        options[:ids] = params[:ids] if params[:ids]
        options[:per_page] = params[:per_page] if params[:per_page]

        if collection.total_pages > 1
          unless collection.previous_page.nil?
            links << link_template % [send(url_helper, resource, options.merge(page: 1)), "first"]
            links << link_template % [send(url_helper, resource, options.merge(page: collection.previous_page)), "prev"]
          end
          unless collection.next_page.nil?
            links << link_template % [send(url_helper, resource, options.merge(page: collection.next_page)), "next"]
            links << link_template % [send(url_helper, resource, options.merge(page: collection.total_pages)), "last"]
          end
        end
        if links.any?
          headers["Links"] = links.join(", ")
        end
      end

      def valid_user
        if current_user.suspended
          status_forbidden
        end
      end
    end
  end
end
