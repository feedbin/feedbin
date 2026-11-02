module Api
  module V3
    # OPML imports. The body is the document itself, not JSON, so the JSON
    # content type check does not apply to create. Limits match the web
    # importer: 500 KB, six uploads per four hours.
    class ImportsController < ApiController
      skip_before_action :validate_content_type, only: :create

      MEDIA_TYPES = %w[text/x-opml application/xml text/xml].freeze
      MAX_BYTES = 500.kilobytes
      UPLOADS = 6
      UPLOAD_PERIOD = 4.hours

      def create
        xml = request.raw_post
        # Cheapest first: nothing is parsed until the size is known.
        return not_opml unless MEDIA_TYPES.include?(request.media_type)
        raise Problems::InvalidParameter.new("The OPML must be smaller than 500 KB.", pointer: "", code: "too_large") if xml.bytesize > MAX_BYTES
        return not_opml unless opml?(xml)
        return rate_limited unless Throttle.throttle!("v3:imports:#{@user.id}", UPLOADS, UPLOAD_PERIOD)

        # A filename puts the import on the web's Import & Export page, where
        # fixable items can be resolved.
        import = @user.imports.new(xml: xml, filename: "#{@token.application&.name || "API"} import")
        if import.save
          render json: ImportSerializer.new(import).to_h, status: :accepted
        else
          status_validation_failed([{pointer: "", code: "invalid_value", detail: "The OPML lists no feeds."}])
        end
      end

      def show
        render json: ImportSerializer.new(@user.imports.includes(:import_items).find(params[:id])).to_h
      end

      private

      def not_opml
        render_problem :unsupported_media_type, "unsupported_media_type",
          title: "Unsupported media type",
          detail: "Send an OPML document as #{MEDIA_TYPES.join(" or ")}."
      end

      def opml?(xml)
        Nokogiri::XML(xml).root&.name&.casecmp?("opml")
      end

      def rate_limited
        response.set_header("Retry-After", UPLOAD_PERIOD.to_i.to_s)
        render_problem :too_many_requests, "rate_limited",
          title: "Rate limited",
          detail: "Too many imports. Try again in a few hours."
      end
    end
  end
end
