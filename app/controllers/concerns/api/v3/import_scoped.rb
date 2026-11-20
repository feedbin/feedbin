module Api
  module V3
    module ImportScoped
      extend ActiveSupport::Concern

      private

      def set_import
        @import = @user.imports.includes(import_items: :discovered_feeds).find(params[:import_id] || params[:id])
      end

      def render_import(status: :ok)
        render json: ImportSerializer.new(@import.reload).to_h, status: status
      end
    end
  end
end
