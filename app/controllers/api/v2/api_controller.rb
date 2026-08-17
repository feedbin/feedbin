module Api
  module V2
    class ApiController < ApplicationController
      MAX_PER_PAGE = 1_000

      skip_before_action :verify_authenticity_token
      before_action :valid_user, if: :signed_in?

      def entries_response(path_helper)
        if params[:read] == "true"
          @page_query = @page_query.where.not(id: @user.unread_entries.select(:entry_id))
        elsif params[:read] == "false"
          @page_query = @page_query.where(id: @user.unread_entries.select(:entry_id))
        end

        if params[:starred] == "true"
          @page_query = @page_query.where(id: @user.starred_entries.select(:entry_id))
        elsif params[:starred] == "false"
          @page_query = @page_query.where.not(id: @user.starred_entries.select(:entry_id))
        end

        return status_bad_request([{since: "Invalid ISO 8601 timestamp"}]) if invalid_since?

        if since_time
          @page_query = @page_query.where("entries.created_at > :time", time: since_time)
        end

        if params.key?(:per_page)
          # will_paginate divides by this, so a zero — which is also what a
          # non-numeric value coerces to — makes total_pages Infinity and
          # out_of_bounds? raise FloatDomainError.
          per_page = params[:per_page].to_i
          return status_bad_request([{per_page: "Must be a positive integer"}]) if per_page < 1
          @page_query = @page_query.per_page([per_page, MAX_PER_PAGE].min)
        end

        ids = @page_query.pluck(:id)
        @entries = Entry.in_order_of(:id, ids).for_api(params[:mode])

        entry_count(@page_query)

        if @page_query.out_of_bounds?
          status_not_found
        elsif !@entries.present?
          render json: []
        else
          links_header(@page_query, path_helper, params[:feed_id])
          if stale?(etag: @entries)
            render_json "entries/index"
          end
        end
      end

      def render_json(template)
        render template: "api/v2/#{template}", formats: :html, layout: nil, content_type: "application/json"
      end

      def entry_count(collection)
        count = 0
        if collection.respond_to?(:total_entries)
          count = collection.total_entries
        elsif collection.respond_to?(:length)
          count = collection.length
        end
        headers["X-Feedbin-Record-Count"] = count.to_s
      end

      def status_too_many_requests
        @error = {status: 429, errors: []}
        render partial: "api/v2/shared/api_error", status: :too_many_requests
      end

      rescue_from ArgumentError do |exception|
        @error = {status: 400, message: "Bad Request", errors: []}
        if exception.message == "invalid date"
          @error[:errors] << {since: "invalid date format"}
        end
        render partial: "api/v2/shared/api_error", status: 400
        ErrorService.notify(exception)
      end

      rescue_from ActiveRecord::RecordNotFound do |exception|
        @error = {status: 404, message: "Not Found", errors: []}
        render partial: "api/v2/shared/api_error", status: 404
        ErrorService.notify(exception)
      end

      rescue_from JSON::ParserError do |exception|
        @error = {status: 400, message: "Problem parsing JSON", errors: []}
        render partial: "api/v2/shared/api_error", status: 400
        ErrorService.notify(exception)
      end

      private

      # Time.iso8601 demands second precision, but "2016-02-01T12:30Z" and
      # "2016-02-01" are both valid ISO 8601 and both what clients send.
      # Parse once, so the filter and the Link header cannot disagree about
      # whether the value was usable.
      def since_time
        return @since_time if defined?(@since_time)
        @since_time = begin
          Time.zone.iso8601(params[:since]) if params[:since].present?
        rescue ArgumentError
          nil
        end
      end

      def invalid_since?
        params[:since].present? && since_time.nil?
      end

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
        unless request.media_type == "application/json"
          @error = {status: 415, message: 'Please use the "Content-Type: application/json; charset=utf-8" header', errors: []}
          render partial: "api/v2/shared/api_error", status: 415
        end
      end

      def needs(*keys)
        needs_nested(params, *keys)
      end

      def needs_nested(parameters, *keys)
        missing = keys.reject { |key| parameters.key? key }
        if missing.present?
          @error = {status: 400, errors: []}
          missing.map { |key| @error[:errors] << {key => "Missing parameter: #{key}"} }
          render(partial: "api/v2/shared/api_error", status: 400) && return
        end
      end

      def links_header(collection, url_helper, resource = nil)
        return if collection.empty?

        links = []
        link_template = '<%s>; rel="%s"'

        options = {format: :json}
        options[:since]           = since_time.iso8601(6)                   if since_time
        options[:read]            = params[:read]                           if params[:read]
        options[:starred]         = params[:starred]                        if params[:starred]
        options[:ids]             = params[:ids]                            if params[:ids]
        options[:per_page]        = params[:per_page]                       if params[:per_page]
        options[:mode]            = params[:mode]                           if params[:mode]
        options[:include_entries] = params[:include_entries]                if params[:include_entries]

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
        if links.present?
          headers["Links"] = links.join(", ")
        end
      end

      def valid_user
        if current_user.suspended || current_user.plan.restricted?
          status_forbidden
        end
      end
    end
  end
end
