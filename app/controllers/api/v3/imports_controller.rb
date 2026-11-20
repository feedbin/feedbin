module Api
  module V3
    class ImportsController < ApiController
      MEDIA_TYPES = %w[text/x-opml application/xml text/xml].freeze
      MAX_BYTES = 500.kilobytes
      UPLOADS = 6
      UPLOAD_PERIOD = 4.hours

      skip_before_action :validate_content_type, only: :create
      before_action :ensure_opml, :throttle, only: :create
      include ImportScoped

      before_action :set_import, only: [:show, :destroy]

      # Newest first, as the web's Import History lists them.
      def index
        imports = @user.imports.where.not(filename: nil).includes(import_items: :discovered_feeds).order(created_at: :desc, id: :desc)
        data = imports.map { ImportSerializer.new(it).to_h }
        return unless stale?(etag: digest(data))
        render_list(data)
      end

      # A filename makes the import show on the web's Import & Export page.
      def create
        import = @user.imports.new(xml: request.raw_post, filename: filename)
        if import.save
          render json: ImportSerializer.new(import).to_h, status: :accepted
        else
          status_validation_failed([{pointer: "", code: "invalid_value", detail: "The OPML lists no feeds."}])
        end
      end

      def show
        render json: ImportSerializer.new(@import).to_h
      end

      # Only the record of it: the subscriptions it made stay.
      def destroy
        @import.destroy!
        head :no_content
      end

      private

      # The file's name when the app sends it, so the web's history can tell one upload from another.
      def filename
        params[:filename].to_s.strip.presence&.truncate(255) || "#{@token.application&.name || "API"} import"
      end

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
