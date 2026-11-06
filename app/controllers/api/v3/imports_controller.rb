module Api
  module V3
    class ImportsController < ApiController
      MEDIA_TYPES = %w[text/x-opml application/xml text/xml].freeze
      MAX_BYTES = 500.kilobytes
      UPLOADS = 6
      UPLOAD_PERIOD = 4.hours

      skip_before_action :validate_content_type, only: :create
      before_action :ensure_opml, :throttle, only: :create

      # A filename makes the import show on the web's Import & Export page.
      def create
        import = @user.imports.new(xml: request.raw_post, filename: "#{@token.application&.name || "API"} import")
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

      # Size is checked before the body is parsed.
      def ensure_opml
        return not_opml unless MEDIA_TYPES.include?(request.media_type)
        raise Problems::InvalidParameter.new("The OPML must be smaller than 500 KB.", pointer: "", code: "too_large") if request.raw_post.bytesize > MAX_BYTES
        not_opml unless Nokogiri::XML(request.raw_post).root&.name&.casecmp?("opml")
      end

      def throttle
        return if Throttle.throttle!("v3:imports:#{@user.id}", UPLOADS, UPLOAD_PERIOD)
        status_rate_limited(retry_after: UPLOAD_PERIOD, detail: "Too many imports. Try again in a few hours.")
      end

      def not_opml
        render_problem :unsupported_media_type, "unsupported_media_type",
          title: "Unsupported media type",
          detail: "Send an OPML document as #{MEDIA_TYPES.join(" or ")}."
      end
    end
  end
end
