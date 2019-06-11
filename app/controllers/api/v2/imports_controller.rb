module Api
  module V2
    class ImportsController < ApiController
      respond_to :json

      before_action :validate_xml, only: [:create]

      def index
        user = current_user
        @imports = user.imports.order(created_at: :desc)
      end

      def create
        user = current_user
        @import = user.imports.create!
        @import.build_opml_import_job(@data)
      end

      def show
        user = current_user
        @import = user.imports.find(params[:id])
      end

      private

      def validate_xml
        @data = request.raw_post.lstrip
        @xml = Nokogiri::XML.parse(@data).css("body outline")
        if @xml.respond_to?(:length) && @xml.length == 0
          @error = {status: 415, message: 'Data does not appear to be OPML', errors: []}
          render partial: "api/v2/shared/api_error", status: 415
        end
      end

    end
  end
end
